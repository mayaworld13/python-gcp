from flask import Flask, render_template
import random

app = Flask(__name__)

quotes = [
    "💡 Believe in yourself — you’re unstoppable!",
    "🚀 Every great dream begins with a dreamer.",
    "🔥 The best time to start was yesterday. The next best time is now.",
    "🌟 Code. Deploy. Repeat. Success follows consistency.",
    "🎯 Focus on progress, not perfection."
]

@app.route('/')
def home():
    message = random.choice(quotes)
    return render_template('index.html', message=message)

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)
