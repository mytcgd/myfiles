const FILE_PATH = process.env.FILE_PATH || './.npm';
const intervalInseconds = process.env.TIME || 100;
const ENABLE_HTTPSERVER = (process.env.ENABLE_HTTPSERVER || 'true').toLowerCase() === 'true';
const DEBUG = (process.env.DEBUG || 'false').toLowerCase() === 'true';
const KEEPALIVE = (process.env.KEEPALIVE || 'false').toLowerCase() === 'true';
const PORT = process.env.PORT || 3000;
const HY2_PORT = process.env.HY2_PORT || process.env.SERVER_PORT || 3001;
const HY2_SNI = process.env.HY2_SNI || 'https://bing.com';
const LOCAL_DOMAIN = process.env.LOCAL_DOMAIN || '';

const UUID = process.env.UUID || '7160b696-dd5e-42e3-a024-145e92cec916';
const NEZHA_SERVER = process.env.NEZHA_SERVER || '';
const NEZHA_PORT = process.env.NEZHA_PORT || '443';
const NEZHA_KEY = process.env.NEZHA_KEY || '';
const SUB_NAME = process.env.SUB_NAME || 'test';
const SUB_URL = process.env.SUB_URL || '';
const MYIP_URL = process.env.MYIP_URL || '';

const axios = require("axios");
const koffi = require("koffi");
const { pipeline } = require('stream/promises');
const os = require('os');
const fs = require("fs");
const path = require("path");
const http = require('http');
const https = require('https');
const exec = require("child_process").exec;
const delay = (ms) => new Promise(resolve => setTimeout(resolve, ms));

process.stdout.on('error', (err) => {
    if (err.code === 'EPIPE') return;
    throw err;
});

function log(level, msg) {
    if (!DEBUG && level === 'DEBUG') return;
    try {
        const timestamp = new Date().toISOString().replace('T', ' ').slice(0, 19);
        console.log(`[${timestamp}] [${level}] ${msg}`);
    } catch (err) {
        if (err.code !== 'EPIPE') throw err;
    }
}
const info = (msg) => log('INFO', msg);
const debug = (msg) => log('DEBUG', msg);
const warn = (msg) => log('WARN', msg);

let hyLib = null, agentLib = null;
let hyRunning = false, agentRunning = false;
let httpServerInstance = null;
let shuttingDown = false;

function loadSo(name, soPath) {
    try {
        const lib = koffi.load(soPath);
        debug(`Loaded ${name}: ${soPath}`);
        return lib;
    } catch (err) {
        debug(`Failed to load ${name}: ${err.message}`);
        return null;
    }
}

function createFolder(folderPath) {
    try {
        fs.statSync(folderPath);
        debug(`${folderPath} already exists`);
    } catch (err) {
        if (err.code === 'ENOENT') {
            fs.mkdirSync(folderPath);
            debug(`${folderPath} is created`);
        } else {
            debug(`${folderPath} create failed`);
        }
    }
}

const pathsToDelete = ['web.so', 'npm.so', 'server.crt', 'server.key', 'log.txt'];
function cleanupOldFiles() {
    for (const file of pathsToDelete) {
        const filePath = path.join(FILE_PATH, file);
        try {
            const stats = fs.statSync(filePath);
            if (stats.isDirectory()) {
                fs.rmSync(filePath, { recursive: true });
                debug(`${filePath} deleted (directory)`);
            } else {
                fs.unlinkSync(filePath);
                debug(`${filePath} deleted (file)`);
            }
        } catch (error) {
            if (error.code !== 'ENOENT') {
                debug(`Failed to delete ${filePath}:`, error);
            }
        }
    }
}

function httpserver() {
    const server = http.createServer((req, res) => {
        if (req.url === '/') {
            res.writeHead(200);
            res.end('hello world');
        } else if (req.url === '/sub') {
            const subFilePath = FILE_PATH + '/log.txt';
            fs.readFile(subFilePath, 'utf8', (error, data) => {
                if (error) {
                    res.writeHead(500);
                    res.end('Error reading file');
                } else {
                    res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' });
                    res.end(data);
                }
            });
        } else {
            res.writeHead(404);
            res.end('Not found');
        }
    });
    httpServerInstance = server;
    server.on('error', (error) => {
        debug(`HTTP server error on port ${PORT}: ${error.message}`);
    });
    server.listen(PORT, () => {
        info(`server is running on port : ${PORT}`);
    });
}

function execPromise(command, options = {}) {
    return new Promise((resolve, reject) => {
        const child = exec(command, options, (error, stdout, stderr) => {
            if (error) {
                const err = new Error(`Command failed: ${error.message}`);
                err.code = error.code;
                err.stderr = stderr.trim();
                reject(err);
            } else {
                resolve(stdout.trim());
            }
        });
    });
}

async function getCertificateAndKey() {
    try {
        const keyPath = path.join(FILE_PATH, "server.key");
        await execPromise(
            `openssl ecparam -genkey -name prime256v1 -out "${keyPath}"`
        );

        const certPath = path.join(FILE_PATH, "server.crt");
        await execPromise(
            `openssl req -x509 -nodes -days 365000 -key "${keyPath}" -out "${certPath}" -subj "/CN=bing.com"`
        );

        debug(`Certificate and key have been successfully generated: ${FILE_PATH}`);

    } catch (error) {
        debug(`OpenSSL command failed with return code ${error.code || 'unknown'}`);
        if (error.stderr) {
            debug(`Stderr: ${error.stderr}`);
        } else {
            debug(`Error: ${error.message}`);
        }
    }
}

function getSystemArchitecture() {
    const arch = os.arch();
    if (arch === 'arm' || arch === 'arm64' || arch === 'aarch64') {
        return 'arm';
    } else {
        return 'amd';
    }
}

function getFilesForArchitecture(architecture) {
    const FILE_URLS = {
        web: {
            arm: "https://github.com/kahunama/myfile/releases/download/native/hy_arm.so",
            amd: "https://github.com/kahunama/myfile/releases/download/native/hy.so"
        },
        npm: {
            arm: "https://github.com/kahunama/myfile/releases/download/native/agent_arm.so",
            amd: "https://github.com/kahunama/myfile/releases/download/native/agent.so"
        }
    };
    let baseFiles = [
        { fileName: "web.so", fileUrl: FILE_URLS.web[architecture] }
    ];

    if (NEZHA_SERVER && NEZHA_PORT && NEZHA_KEY) {
        baseFiles.push({
            fileName: "npm.so",
            fileUrl: FILE_URLS.npm[architecture]
        });
    }

    return baseFiles;
}

async function download_function(fileName, fileUrl) {
    const filePath = path.join(FILE_PATH, fileName);
    let downloadSuccess = false;

    try {
        fs.statSync(filePath);
        debug(`File ${fileName} already exists, skipping download.`);
        downloadSuccess = true;
    } catch (error) {
        if (error.code === 'ENOENT') {
            try {
                const response = await axios({
                    method: 'get',
                    url: fileUrl,
                    responseType: 'stream',
                });
                await pipeline(response.data, fs.createWriteStream(filePath));
                debug(`Download ${fileName} successfully`);
                downloadSuccess = true;
            } catch (err) {
                debug(`Download ${fileName} failed: ${err.message}`);
            }
        } else {
            debug(`File ${fileName} access error: ${error.message}`);
        }
    }

    return { fileName, filePath, success: downloadSuccess };
}

async function downloadFiles() {
    const architecture = getSystemArchitecture();
    const filesToDownload = getFilesForArchitecture(architecture);

    const downloadResults = await Promise.all(
        filesToDownload.map(file =>
        download_function(file.fileName, file.fileUrl)
        )
    );

    for (const { fileName, filePath, success } of downloadResults) {
        if (success) {
            try {
                fs.chmodSync(filePath, 0o755);
                debug(`Empowerment success for ${fileName}: 755`);
            } catch (err) {
                debug(`Empowerment failed for ${fileName}: ${err.message}`);
            }
        }
    }
}

function getwebConfig() {
    return {
        listen: `:${HY2_PORT}`,
        cert: path.join(FILE_PATH, "server.crt"),
        key: path.join(FILE_PATH, "server.key"),
        auth: {
            type: "password",
            password: UUID
        },
        masquerade: {
            type: "proxy",
            proxy: {
                url: HY2_SNI,
                rewriteHost: true
            }
        }
    };
}

function getAgentConfig() {
    const tlsPorts = ['443', '8443', '2096', '2087', '2083', '2053'];
    const useTls = tlsPorts.includes(NEZHA_PORT);

    return {
        Debug: false,
        Server: `${NEZHA_SERVER}:${NEZHA_PORT}`,
        ClientSecret: NEZHA_KEY,
        UUID: UUID,
        DisableAutoUpdate: true,
        DisableForceUpdate: true,
        DisableCommandExecute: false,
        GPU: false,
        Temperature: false,
        TLS: useTls,
        InsecureTLS: false,
        ReportDelay: 4,
        SkipConnectionCount: true,
        SkipProcsCount: true,
        DisableNat: false,
        DisableSendQuery: false,
        IPReportPeriod: 1800,
        UseGiteeToUpgrade: false,
        UseIPv6CountryCode: false,
        Quiet: !DEBUG
    };
}

async function runweb() {
    const soPath = path.join(FILE_PATH, 'web.so');
    try {
        fs.statSync(soPath);
    } catch (error) {
        if (error.code === 'ENOENT') {
            debug('web.so file not found, skip running');
            return;
        }
        debug(`web.so stat error: ${error}`);
        return;
    }

    if (hyRunning) {
        debug('web is already running, skip');
        return;
    }

    try {
        hyLib = loadSo('hysteria2', soPath);
        if (!hyLib) return;

        const startFn = hyLib.func('int StartHysteriaServer(str)');
        const stopFn = hyLib.func('int StopHysteriaServer()');
        const versionFn = hyLib.func('str HysteriaVersion()');

        try {
            const ver = versionFn();
            debug(`hysteria version: ${ver}`);
        } catch (e) {
            debug(`hysteria version check failed: ${e.message}`);
        }

        const config = getwebConfig();
        const configJson = JSON.stringify(config);

        hyRunning = true;
        startFn.async(configJson, (err, code) => {
            if (err) {
                debug(`web FFI error: ${err.message}`);
            } else if (code !== 0) {
                debug(`web exited with code: ${code}`);
            } else {
                debug(`web exited with code: ${code}`);
            }
            hyRunning = false;
        });

        debug('web started via FFI');
    } catch (error) {
        debug(`web FFI load error: ${error.message}`);
        hyRunning = false;
    }
}

function stopweb() {
    if (!hyLib || !hyRunning) {
        debug('web not running, skip stop');
        return;
    }
    try {
        const stopFn = hyLib.func('int StopHysteriaServer()');
        stopFn.async((err, code) => {
            if (err) debug(`web stop error: ${err.message}`);
            else debug(`web stop returned: ${code}`);
            hyRunning = false;
        });
        debug('web stop signal dispatched asynchronously');
    } catch (err) {
        debug(`web stop error: ${err.message}`);
    }
}

async function runnpm() {
    const soPath = path.join(FILE_PATH, 'npm.so');
    try {
        fs.statSync(soPath);
    } catch (error) {
        if (error.code === 'ENOENT') {
            debug('npm.so file not found, skip running');
            return;
        }
        debug(`npm.so stat error: ${error}`);
        return;
    }

    if (agentRunning) {
        debug('agent is already running, skip');
        return;
    }

    try {
        agentLib = loadSo('agent', soPath);
        if (!agentLib) return;

        const startFn = agentLib.func('int StartNezhaAgent(str)');
        const stopFn = agentLib.func('int StopNezhaAgent()');

        const config = getAgentConfig();
        const configJson = JSON.stringify(config);

        debug(`agent config: ${configJson}`);

        agentRunning = true;
        startFn.async(configJson, (err, code) => {
            if (err) {
                debug(`agent FFI error: ${err.message}`);
            } else if (code !== 0) {
                debug(`agent exited with code: ${code}`);
            } else {
                debug(`agent exited with code: ${code}`);
            }
            agentRunning = false;
        });

        debug('agent started via FFI');
    } catch (error) {
        debug(`agent FFI load error: ${error.message}`);
        agentRunning = false;
    }
}

function stopnpm() {
    if (!agentLib || !agentRunning) {
        debug('agent not running, skip stop');
        return;
    }
    try {
        const stopFn = agentLib.func('int StopNezhaAgent()');
        stopFn.async((err, code) => {
            if (err) debug(`agent stop error: ${err.message}`);
            else debug(`agent stop returned: ${code}`);
            agentRunning = false;
        });
        debug('agent stop signal dispatched asynchronously');
    } catch (err) {
        debug(`agent stop error: ${err.message}`);
    }
}

async function runapp() {
    await getCertificateAndKey();

    await runweb();
    await delay(1000);
    debug('web is running');

    if (NEZHA_SERVER && NEZHA_PORT && NEZHA_KEY) {
        await runnpm();
        await delay(1000);
        debug('agent is running');
    } else {
        debug('npm variable is empty, skip running');
    }
}

async function keep_alive() {
    if (hyRunning) {
        debug("web is already running");
    } else {
        debug('web runs again !');
        await runweb();
    }

    await delay(5000);

    if (NEZHA_SERVER && NEZHA_PORT && NEZHA_KEY) {
        if (agentRunning) {
            debug("agent is already running");
        } else {
            debug('agent runs again !');
            await runnpm();
        }
    }
}

function cleanString(str) {
    if (typeof str === 'string') {
        let result = str;
        result = result.replace(/[\s,.]/g, '_');
        result = result.replace(/_+/g, '_');

        if (result.startsWith('_')) {
            result = result.substring(1);
        }
        if (result.endsWith('_')) {
            result = result.slice(0, -1);
        }

        return result;
    }
    return str;
}

let ISP = 'UN', MYIP = '1.1.1.1';
async function getipandisp() {
    const ipapiurl = [
        'https://api.ip.sb/geoip/',
        'http://ip-api.com/json/',
        ...(MYIP_URL.trim() !== '' ? [MYIP_URL] : [])
    ];

    for (const url of ipapiurl) {
        try {
            const response = await axios.get(url, { timeout: 3000 });
            const data = response.data;

            if (data.ip || data.query) {
                const rawIp = data.ip || data.query;
                MYIP = rawIp.includes(':') ? `[${rawIp}]` : rawIp;
                const country = data.country_code || data.countryCode || 'UN';
                const ispName = cleanString(data.isp) || 'Unknown';
                ISP = `${country}_${ispName.replace(/ /g, '_')}`;
                return;
            }
        } catch (error) {
            debug(`Request to ${url} failed, trying the next one`);
        }
    }
}

let UPLOAD_DATA = '';
function generateLinks() {
    let myaddress;
    if (LOCAL_DOMAIN) {
        myaddress = LOCAL_DOMAIN;
    } else {
        myaddress = MYIP
    }

    UPLOAD_DATA = `hysteria2://${UUID}@${myaddress}:${HY2_PORT}/?sni=www.bing.com&alpn=h3&insecure=1#${ISP}-${SUB_NAME}`;
    if (UPLOAD_DATA) {
        const filePath = path.join(FILE_PATH, 'log.txt');
        fs.writeFileSync(filePath, Buffer.from(UPLOAD_DATA).toString('base64'));
        debug(Buffer.from(UPLOAD_DATA).toString('base64'));
    }
    return UPLOAD_DATA;
}

async function uploadSubscription(SUB_NAME, UPLOAD_DATA, SUB_URL) {
    const connectTimeout = 10000;
    const readTimeout = 30000;
    const payload = JSON.stringify({ URL_NAME: SUB_NAME, URL: UPLOAD_DATA });
    const postData = Buffer.from(payload, 'utf8');

    try {
        const parsedUrl = new URL(SUB_URL);
        const isHttps = parsedUrl.protocol === 'https:';
        const transport = isHttps ? https : http;
        const options = {
            hostname: parsedUrl.hostname,
            port: parsedUrl.port || (isHttps ? 443 : 80),
            path: parsedUrl.pathname + (parsedUrl.search || ''),
            method: 'POST',
            headers: {
                'Content-Type': 'application/json; charset=utf-8',
                'Content-Length': postData.length
            }
        };

        const responseBody = await new Promise((resolve, reject) => {
            let connectTimer;
            const req = transport.request(options, (res) => {
                clearTimeout(connectTimer);
                if (res.statusCode < 200 || res.statusCode >= 300) {
                    res.resume();
                    reject(new Error(`HTTP error! status: ${res.statusCode}, response: ${res.statusMessage}`));
                    return;
                }

                let responseBody = '';
                res.setEncoding('utf8');
                res.setTimeout(readTimeout, () => {
                    res.destroy(new Error('Subscription upload read timeout'));
                });
                res.on('data', (chunk) => responseBody += chunk);
                res.on('end', () => resolve(responseBody));
                res.on('error', reject);
            });

            connectTimer = setTimeout(() => {
                req.destroy(new Error('Subscription upload connection timeout'));
            }, connectTimeout);

            req.on('error', (error) => {
                clearTimeout(connectTimer);
                reject(error);
            });
            req.write(postData);
            req.end();
        });

        debug('Subscription uploaded successfully');
        return [true, responseBody];
    } catch (error) {
        debug(`Subscription upload failed: ${error.message}`);
        return [false, null];
    }
}

function cleanfiles() {
    setTimeout(() => {
        let filesToDelete;
        if (KEEPALIVE) {
            filesToDelete = [];
        } else {
            filesToDelete = [
                `${FILE_PATH}/web.so`,
                `${FILE_PATH}/npm.so`,
                `${FILE_PATH}/server.crt`,
                `${FILE_PATH}/server.key`
            ];
        }

        filesToDelete.forEach(filePath => {
            try {
                const stats = fs.statSync(filePath);

                if (stats.isDirectory()) {
                    fs.rmSync(filePath, { recursive: true });
                } else {
                    fs.unlinkSync(filePath);
                }
                debug(`${filePath} deleted`);
            } catch (error) {
                if (error.code !== 'ENOENT') {
                    debug(`Failed to delete ${filePath}: ${error}`);
                }
            }
        });
    }, 60000);
}

function gracefulExit(signalName = 'SIGINT') {
    if (shuttingDown) return;
    shuttingDown = true;
    info(`Shutting down (${signalName})...`);
    process.kill(process.pid, 'SIGKILL');
}

process.on('SIGINT', () => gracefulExit('SIGINT'));
process.on('SIGTERM', () => gracefulExit('SIGTERM'));

async function main() {
    info("Starting Server...")
    createFolder(FILE_PATH);
    cleanupOldFiles();
    await downloadFiles();
    await delay(5000);
    await getipandisp();
    await runapp();
    generateLinks();
    if (ENABLE_HTTPSERVER) {
        httpserver();
    } else {
        debug('HTTP server disabled by ENABLE_HTTPSERVER=false');
    }
    cleanfiles();

    if (SUB_URL && SUB_NAME) {
        const [uploaded] = await uploadSubscription(SUB_NAME, UPLOAD_DATA, SUB_URL);
        if (!uploaded) {
            debug('Initial subscription upload failed; services will continue running');
        }
    }
    if (KEEPALIVE) {
        await keep_alive();
        setInterval(() => {
            keep_alive().catch((error) => debug(`keep_alive failed: ${error.message}`));
        }, intervalInseconds * 1000);
    }
}

main().catch((error) => {
    debug(`Fatal startup error: ${error.stack || error.message}`);
    process.exitCode = 1;
});
