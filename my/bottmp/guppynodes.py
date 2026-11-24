#!/usr/bin/env python

import os
import re
import shutil
import ctypes
from ctypes import c_int, c_char_p, c_void_p
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
ENABLE_HTTPSERVER = os.environ.get('ENABLE_HTTPSERVER', 'false').lower() == 'true'
DEBUG = os.environ.get('DEBUG', 'false').lower() == 'true'
KEEPALIVE = os.environ.get('KEEPALIVE', 'false').lower() == 'true'
HTTP_PORT = int(os.environ.get('HTTP_PORT') or 3000)
MYIP_URL = os.environ.get('MYIP_URL', '')

PORT_DIRECT = int(os.environ.get('PORT_DIRECT') or 10000)
TUNNEL_PORT = int(os.environ.get('PORT') or 0)
V_V4_PORT = os.environ.get('V_V4_PORT', '')
V_V6_PORT = os.environ.get('V_V6_PORT', '30000')
GOST_KEY = os.environ.get('GOST_KEY', '4b793564-dbcc-4adf-9857-83357c54157e')
CF_V4_DOMAIN = os.environ.get('CF_V4_DOMAIN', '')
CF_V6_DOMAIN = os.environ.get('CF_V6_DOMAIN', 'v6.tcgd.nyc.mn')
ARGO_DOMAIN = os.environ.get('ARGO_DOMAIN', '')
MY_DOMAIN = os.environ.get('MY_DOMAIN', '192.168.3.12')
GOST_LOG_LEVEL = os.environ.get('GOST_LOG_LEVEL') or ('debug' if DEBUG else 'warn')

UUID = os.environ.get('UUID', '197c5da2-72d2-4274-a182-5b35712eccb7')
NEZHA_SERVER = os.environ.get('NEZHA_SERVER', 'my.tcguangda.eu.org')
NEZHA_KEY = os.environ.get('NEZHA_KEY', 'ilovehesufeng520')
NEZHA_PORT = os.environ.get('NEZHA_PORT', '443')
SUB_NAME = os.environ.get('SUB_NAME', 'guppynodes')
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

pathsToDelete = ['gost.so', 'npm.so']
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

class MyHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass

    def do_GET(self):
        if self.path == '/':
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b'Hello, world')
        else:
            self.send_response(404)
            self.end_headers()
            self.wfile.write(b'Not found')

def start_http_server():
    try:
        global http_server
        server = HTTPServer(('0.0.0.0', HTTP_PORT), MyHandler)
        server.timeout = 0.5
        http_server = server
        debug(f"✅ server is running on port {HTTP_PORT}")
        server.serve_forever()
    except OSError as e:
        debug(f"HTTP server failed on port {HTTP_PORT}: {e}")
    except Exception as e:
        try:
            print(f"HTTP server stopped: {e}")
        except (BrokenPipeError, OSError):
            pass

gost_lib = None
gost_running = False
agent_lib = None
agent_running = False
http_server = None
shutdown_started = False

try:
    _libc = ctypes.CDLL(None)
    _libc.free.argtypes = [c_void_p]
    _libc.free.restype = None
except Exception:
    _libc = None

def _take_cstring(value):
    if not value:
        return ''
    try:
        return ctypes.cast(value, c_char_p).value.decode('utf-8', 'replace')
    finally:
        if _libc:
            _libc.free(value)

def _ffi_thread(name, start_fn, config_json, on_exit):
    try:
        code = start_fn(config_json.encode('utf-8'))
        debug(f"{name} exited with code: {code}")
    except Exception as e:
        debug(f"{name} FFI error: {e}")
    finally:
        on_exit()

def get_files_for_architecture():
    arch = os.uname().machine
    is_arm = arch in ['arm', 'arm64', 'aarch64']
    suffix = '_arm' if is_arm else ''

    base_files = [
        {'file_name': 'gost.so', 'file_url': f'https://github.com/kahunama/myfile/releases/download/native/gost{suffix}.so'},
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

def gost_config():
    socks_port = TUNNEL_PORT if (ARGO_DOMAIN and TUNNEL_PORT) else PORT_DIRECT
    if ARGO_DOMAIN and not TUNNEL_PORT:
        debug(f"ARGO_DOMAIN is set but PORT is empty; falling back to using PORT_DIRECT={PORT_DIRECT}")

    services = [{
        "name": "socks",
        "addr": f"127.0.0.1:{socks_port}",
        "handler": {"type": "socks5"},
        "listener": {"type": "tcp"},
    }]
    chains = []

    if ARGO_DOMAIN:
        targets = [("argo", ARGO_DOMAIN, V_V4_PORT)]
    else:
        targets = []
        if CF_V4_DOMAIN:
            targets.append(("v4", CF_V4_DOMAIN, V_V4_PORT))
        if CF_V6_DOMAIN:
            targets.append(("v6", CF_V6_DOMAIN, V_V6_PORT))
        if not targets:
            debug("CF_V4_DOMAIN, CF_V6_DOMAIN, and ARGO_DOMAIN are all empty; only the local SOCKS5 proxy will be started.")

    for tag, domain, port in targets:
        if not port:
            debug(f"{tag} Domain {domain} lacks a corresponding port; skipping this relay.")
            continue
        relay_host, _, relay_port = domain.partition(':')
        relay_addr = f"{relay_host}:{relay_port or 80}"
        chain_name = f"chain-{tag}"
        chains.append({
            "name": chain_name,
            "hops": [{
                "name": f"hop-{tag}",
                "nodes": [{
                    "name": f"node-{tag}",
                    "addr": relay_addr,
                    "connector": {"type": "relay"},
                    "dialer": {
                        "type": "ws",
                        "metadata": {"path": f"/{GOST_KEY}", "host": relay_host},
                    },
                }],
            }],
        })
        services.append({
            "name": f"rtcp-{tag}",
            "addr": f":{port}",
            "handler": {"type": "rtcp"},
            "listener": {"type": "rtcp", "chain": chain_name},
            "forwarder": {
                "nodes": [{"name": "socks-target", "addr": f"127.0.0.1:{socks_port}"}],
            },
        })

    config = {
        "log": {"level": GOST_LOG_LEVEL},
        "services": services,
    }
    if chains:
        config["chains"] = chains
    debug(f"gost FFI config: {json.dumps(config)}")
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

async def rungost():
    global gost_lib, gost_running

    so_path = os.path.join(FILE_PATH, 'gost.so')
    if not os.path.exists(so_path):
        debug('gost.so file not found, skip running')
        return
    if gost_running:
        debug('gost is already running, skip')
        return

    try:
        if gost_lib is None:
            gost_lib = ctypes.CDLL(so_path)
            debug(f"Loaded gost.so: {so_path}")

            gost_lib.StartGost.argtypes = [c_char_p]
            gost_lib.StartGost.restype = c_int
            gost_lib.StartGostFile.argtypes = [c_char_p]
            gost_lib.StartGostFile.restype = c_int
            gost_lib.StopGost.argtypes = []
            gost_lib.StopGost.restype = c_int
            gost_lib.ReloadGost.argtypes = []
            gost_lib.ReloadGost.restype = c_int
            gost_lib.IsGostRunning.argtypes = []
            gost_lib.IsGostRunning.restype = c_int
            gost_lib.GostVersion.argtypes = []
            gost_lib.GostVersion.restype = c_void_p
            gost_lib.GostLastError.argtypes = []
            gost_lib.GostLastError.restype = c_void_p

            try:
                ver = _take_cstring(gost_lib.GostVersion())
                if ver:
                    debug(f"gost version: {ver}")
            except Exception:
                pass

        config = gost_config()
        config_json = json.dumps(config)

        def on_exit():
            global gost_running
            gost_running = False
            try:
                err = _take_cstring(gost_lib.GostLastError())
                if err:
                    debug(f"gost last error: {err}")
            except Exception:
                pass

        gost_running = True
        t = threading.Thread(target=_ffi_thread,
                             args=('gost', gost_lib.StartGost, config_json, on_exit),
                             daemon=True)
        t.start()
        debug('gost started via FFI')
    except Exception as e:
        debug(f"gost FFI error: {e}")
        gost_running = False

def stopgost():
    global gost_lib, gost_running
    if not gost_lib or not gost_running:
        debug('gost not running, skip stop')
        return
    try:
        gost_lib.StopGost()
        debug('gost stop signal sent')
    except Exception as e:
        debug(f"gost stop error: {e}")

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
    await rungost()
    await asyncio.sleep(1)
    if gost_is_alive():
        debug("gost is running")
    else:
        debug("gost failed to start; keepalive will retry")

    if NEZHA_SERVER and NEZHA_PORT and NEZHA_KEY:
        await runnpm()
        await asyncio.sleep(1)
        debug("agent is running")
    else:
        debug("nezha variable is empty, skip running")

def gost_is_alive():
    if not gost_lib or not gost_running:
        return False
    try:
        return bool(gost_lib.IsGostRunning())
    except Exception:
        return gost_running

async def keep_alive():
    global gost_running
    if gost_is_alive():
        debug("gost is already running")
    else:
        debug("gost runs again !")
        stopgost()
        gost_running = False
        await asyncio.sleep(1)
        await rungost()

    await asyncio.sleep(5)

    if NEZHA_SERVER and NEZHA_PORT and NEZHA_KEY:
        global agent_running
        if agent_running:
            debug("agent is already running")
        else:
            debug("agent runs again !")
            await runnpm()

def generate_links(MYIP, ISP):
    if MY_DOMAIN:
        myaddress = MY_DOMAIN
    else:
        myaddress = MYIP

    if ARGO_DOMAIN:
        links = [f"socks://Og%3D%3D@{myaddress}:{V_V4_PORT}#{ISP}-{SUB_NAME}"]
    else:
        links = []
        if CF_V4_DOMAIN:
            links.append(f"socks://Og%3D%3D@{myaddress}:{V_V4_PORT}#{ISP}-{SUB_NAME}")
        if CF_V6_DOMAIN:
            links.append(f"socks://Og%3D%3D@{myaddress}:{V_V6_PORT}#{ISP}-{SUB_NAME}")

    node_data = '\n'.join(links)
    return node_data

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
            os.path.join(FILE_PATH, 'gost.so'),
            os.path.join(FILE_PATH, 'npm.so'),
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
