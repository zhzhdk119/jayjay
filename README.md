# Public installer compatibility check

Manually dispatched Ubuntu 24.04 ARM test of the already public `cc-host-kit` installer.
Installs browser dependencies and renders only the bundled local start page.
`PRIME_INSTALL_ONLY=1` skips signing-key creation, registration, and collector services.
No account login, production data, credentials, or browser session data is used.
