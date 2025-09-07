from flask import Flask, request, make_response, render_template_string
from markupsafe import escape

app = Flask(__name__)

# A tight, but realistic CSP for this tiny app.
# No inline scripts, no external JS.
CSP = (
    "default-src 'self'; "
    "script-src 'self'; "
    "style-src 'self'; "
    "img-src 'self' data:; "
    "frame-ancestors 'none'; "           # Anti-clickjacking (modern)
    "base-uri 'self'; "
    "object-src 'none'; "
    "form-action 'self'"
)

PERMISSIONS_POLICY = (
    "camera=(), microphone=(), geolocation=(self), "
    "fullscreen=(self), clipboard-read=(), clipboard-write=()"
)

# Cross-origin isolation / Spectre hardening
CORP  = "same-origin"     # Cross-Origin-Resource-Policy
COOP  = "same-origin"     # Cross-Origin-Opener-Policy
COEP  = "require-corp"    # Cross-Origin-Embedder-Policy

def add_security_headers(resp):
    # Core headers per ZAP:
    resp.headers["Content-Security-Policy"] = CSP
    resp.headers["X-Frame-Options"] = "DENY"  # Legacy anti-clickjacking; CSP already covers it.
    resp.headers["Permissions-Policy"] = PERMISSIONS_POLICY
    resp.headers["X-Content-Type-Options"] = "nosniff"
    resp.headers["Referrer-Policy"] = "no-referrer"
    resp.headers["Cross-Origin-Resource-Policy"] = CORP
    resp.headers["Cross-Origin-Opener-Policy"] = COOP
    resp.headers["Cross-Origin-Embedder-Policy"] = COEP

    # Hide server details (ZAP: server version leak)
    resp.headers["Server"] = "secure"

    # Dynamic pages: avoid caching (ZAP informational)
    resp.headers["Cache-Control"] = "no-store"
    resp.headers["Pragma"] = "no-cache"

    # for future imorivement (HTTPs)
    # resp.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains; preload"
    return resp

@app.after_request
def secure_headers(resp):
    return add_security_headers(resp)

@app.route("/health")
def health():
    return "ok", 200

@app.route("/")
def index():
    html = "<h1>Demo App</h1><p>Go to /greet?name=YourName</p>"
    return make_response(render_template_string(html))

# FIXED: reflected XSS — we now escape user input before rendering.
@app.route("/greet")
def greet():
    name = request.args.get("name", "Guest")
    safe_name = escape(name)  # prevents reflected XSS
    html = f"<h2>Hello {safe_name}!</h2>"
    return make_response(render_template_string(html))

if __name__ == "__main__":
    # Bind to 0.0.0.0:8080 as before, no debug mode.
    app.run(host="0.0.0.0", port=8080, debug=False)
