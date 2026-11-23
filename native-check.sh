#!/bin/bash
set -euo pipefail
mkdir -p /tmp/native1800/input /tmp/native1800/public
cd /tmp/native1800
uname -m; grep PRETTY_NAME /etc/os-release
echo "SOURCE_COMMIT=$GITHUB_SHA"
curl -fsSL https://cc-host-kit.vercel.app/kit.tgz -o baseline.tgz
echo '686bb1555b6c1735de9376e5fa59bfc22659917eae2c0f6c587974db7cc21be0  baseline.tgz' | sha256sum -c -
tar xzf baseline.tgz -C input
curl -fsSL "https://raw.githubusercontent.com/$GITHUB_REPOSITORY/$GITHUB_SHA/install.sh" -o input/install.sh
curl -fsSL "https://raw.githubusercontent.com/$GITHUB_REPOSITORY/$GITHUB_SHA/boot.sh.tmpl" -o boot.sh.tmpl
sha256sum input/install.sh boot.sh.tmpl
tar czf public/kit.tgz -C input .
SHA=$(sha256sum public/kit.tgz | cut -d' ' -f1)
sed -e 's|__BASE__|http://127.0.0.1:8765|g' -e "s/__SHA__/$SHA/g" boot.sh.tmpl > public/boot.sh
python3 -m http.server 8765 --bind 127.0.0.1 --directory public >/tmp/native1800-http.log 2>&1 &
HTTP_PID=$!
trap 'kill "$HTTP_PID" 2>/dev/null || true' EXIT
sleep 1
id ubuntu >/dev/null 2>&1 || sudo useradd -m -s /bin/bash ubuntu
printf 'ubuntu ALL=(ALL) NOPASSWD: ALL\n' | sudo tee /etc/sudoers.d/prime-ci-ubuntu >/dev/null
sudo chmod 440 /etc/sudoers.d/prime-ci-ubuntu
sudo -u ubuntu sudo -n env PRIME_INSTALL_ONLY=1 bash public/boot.sh >/tmp/native1800-install.log 2>&1 || { tail -70 /tmp/native1800-install.log; exit 1; }
grep -E '^\[|INSTALL_ONLY|Chrom' /tmp/native1800-install.log
test ! -e /etc/prime-collector/host_key.pem
echo NO_HOST_KEY=PASS
test -z "$(pgrep -u prime -f '[a]gent.py run' || true)"
echo NO_AGENT=PASS
sudo -u prime -H google-chrome --version
cloudflared --version
timeout 60 sudo -u prime -H google-chrome --headless --disable-gpu --user-data-dir=/tmp/native1800-browser --dump-dom file:///opt/prime-collector/kit/start.html >/tmp/native1800-dom.html 2>/tmp/native1800-browser.log || { tail -30 /tmp/native1800-browser.log; exit 1; }
grep -q 'self.baemin.com' /tmp/native1800-dom.html
echo ARM_HEADLESS_LOCAL_PAGE=PASS
if sudo env PRIME_INSTALL_ONLY=invalid bash /opt/prime-collector/kit/install.sh >/tmp/invalid-mode.log 2>&1; then echo INVALID_MODE_REJECT=FAIL; exit 1; fi
echo INVALID_MODE_REJECT=PASS
test ! -e /etc/prime-collector/host_key.pem
echo NATIVE_ARM_CHECK=PASS
