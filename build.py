import os
import sys
import time
import json
import zipfile
import subprocess
import urllib.request
import urllib.error
import ssl
# Fix macOS Python certificate verification quirk
try:
    ssl._create_default_https_context = ssl._create_unverified_context
except AttributeError:
    pass

REPO = "PSandLab/RolleiMeter"
WORKFLOW = "build.yml"
DOWNLOADS_DIR = os.path.expanduser("~/Downloads")

def get_token():
    # Automatically read token from macOS Keychain (saved from your earlier git push)
    try:
        p = subprocess.Popen(
            ['git', 'credential', 'fill'],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
        )
        out, _ = p.communicate(input='protocol=https\nhost=github.com\n')
        for line in out.splitlines():
            if line.startswith('password='):
                return line.split('password=', 1)[1].strip()
    except Exception:
        pass
    token = os.environ.get("GITHUB_TOKEN")
    if token:
        return token
    print("❌ Could not find your GitHub token automatically.")
    return input("Paste your GitHub Personal Access Token (ghp_...): ").strip()

class SafeRedirect(urllib.request.HTTPRedirectHandler):
    # Prevents Amazon/Azure download redirects from clashing with GitHub Auth
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        m = super().redirect_request(req, fp, code, msg, headers, newurl)
        if m is not None and "api.github.com" not in newurl.lower():
            m.headers = {k: v for k, v in m.headers.items() if k.lower() != 'authorization'}
        return m

opener = urllib.request.build_opener(SafeRedirect)

def api_req(url, token, data=None):
    headers = {
        "Authorization": f"Bearer {token}",
        "Accept": "application/vnd.github+json",
        "User-Agent": "RolleiMeter-AutoBuilder"
    }
    body = json.dumps(data).encode("utf-8") if data else None
    req = urllib.request.Request(url, data=body, headers=headers)
    try:
        with opener.open(req) as resp:
            content = resp.read()
            return json.loads(content.decode("utf-8")) if content else {}
    except urllib.error.HTTPError as e:
        print(f"❌ GitHub API Error ({e.code}): {e.read().decode('utf-8')}")
        sys.exit(1)

def main():
    print("\n🚀 --- RolleiMeter Auto-Builder ---")
    token = get_token()
    if not token:
        print("❌ No token provided. Exiting.")
        sys.exit(1)

    print("📡 Triggering 'Build IPA' on GitHub...")
    trigger_url = f"https://api.github.com/repos/{REPO}/actions/workflows/{WORKFLOW}/dispatches"
    api_req(trigger_url, token, data={"ref": "main"})
    print("  [✓] Workflow triggered successfully!")

    print("⏳ Waiting for build to start...")
    time.sleep(5)

    # Find the newly triggered run
    runs_url = f"https://api.github.com/repos/{REPO}/actions/workflows/{WORKFLOW}/runs?per_page=1"
    run_info = api_req(runs_url, token)
    if not run_info.get("workflow_runs"):
        print("❌ Could not locate the workflow run.")
        sys.exit(1)

    run_id = run_info["workflow_runs"][0]["id"]
    print(f"🔨 GitHub is building your IPA (Run ID: {run_id})")

    # Poll status with a clean live timer
    start_time = time.time()
    while True:
        elapsed = int(time.time() - start_time)
        mins, secs = divmod(elapsed, 60)
        status_info = api_req(f"https://api.github.com/repos/{REPO}/actions/runs/{run_id}", token)
        status = status_info.get("status")
        conclusion = status_info.get("conclusion")

        sys.stdout.write(f"\r⏱️  Elapsed: {mins}m {secs:02d}s · Status: {status}...   ")
        sys.stdout.flush()

        if status == "completed":
            print("\n")
            if conclusion == "success":
                print("✅ Build succeeded!")
                break
            else:
                print(f"❌ Build finished with status: {conclusion}")
                sys.exit(1)

        time.sleep(10)

    # Locate the artifact
    print("📦 Locating finished IPA artifact...")
    artifacts_url = f"https://api.github.com/repos/{REPO}/actions/runs/{run_id}/artifacts"
    artifacts = api_req(artifacts_url, token)
    artifact_list = artifacts.get("artifacts", [])

    if not artifact_list:
        print("❌ No artifact found for this build.")
        sys.exit(1)

    artifact = artifact_list[0]
    download_url = artifact["archive_download_url"]
    temp_zip = os.path.join(DOWNLOADS_DIR, "RolleiMeter_temp.zip")

    print(f"⬇️  Downloading '{artifact['name']}' to your Downloads folder...")
    headers = {
        "Authorization": f"Bearer {token}",
        "Accept": "application/vnd.github+json",
        "User-Agent": "RolleiMeter-AutoBuilder"
    }
    req = urllib.request.Request(download_url, headers=headers)
    with opener.open(req) as resp, open(temp_zip, "wb") as f:
        f.write(resp.read())

    # Extract the .ipa out of the GitHub zip wrapper
    print("📂 Unpacking RolleiMeter.ipa...")
    with zipfile.ZipFile(temp_zip, "r") as z:
        z.extractall(DOWNLOADS_DIR)

    if os.path.exists(temp_zip):
        os.remove(temp_zip)

    final_ipa = os.path.join(DOWNLOADS_DIR, "RolleiMeter.ipa")
    print(f"\n🎉 DONE! Saved to: {final_ipa}")
    
    # Reveal in Finder
    subprocess.run(["open", "-R", final_ipa])

if __name__ == "__main__":
    main()
