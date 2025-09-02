from flask import Flask, request
app = Flask(__name__)

@app.route("/")
def index():
    return "<h1>Demo App</h1><p>Go to /greet?name=YourName</p>"

# Intentionally vulnerable: reflected XSS (no sanitization)
@app.route("/greet")
def greet():
    name = request.args.get("name", "Guest")
    return f"<h2>Hello {name}!</h2>"

if __name__ == "__main__":
    # 8080 to match pipeline + Dockerfile
    app.run(host="0.0.0.0", port=8080, debug=False)
