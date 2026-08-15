from flask import Flask, request, jsonify
from flask_cors import CORS
from google import genai
import os
import time
from datetime import datetime
from zoneinfo import ZoneInfo

app = Flask(__name__)
CORS(app)

# ============================================================
# GEMINI API
# ============================================================

api_key = os.getenv("GEMINI_API_KEY")

if not api_key:
    print("WARNING: GEMINI_API_KEY is not set!")

client = genai.Client(api_key=api_key)


# ============================================================
# HOME / TEST ROUTE
# ============================================================

@app.route("/")
def home():
    return "NEXA AI backend is running!"


# ============================================================
# HEALTH CHECK
# ============================================================

@app.route("/health", methods=["GET"])
def health():
    return jsonify({
        "status": "ok",
        "message": "NEXA backend is connected"
    })


# ============================================================
# CHAT
# ============================================================

@app.route("/chat", methods=["POST"])
def chat():

    try:

        data = request.get_json(silent=True)

        if not data:
            return jsonify({
                "response": "No data received."
            }), 400

        message = data.get("message", "").strip()

        if not message:
            return jsonify({
                "response": "Please say something."
            }), 400

        message_lower = message.lower()


        # ====================================================
        # TIME
        # ====================================================

        time_words = [
            "time",
            "what time",
            "current time",
            "time now",
            "tell me the time",
            "what is the time",
            "what's the time",
            "ಸಮಯ",
            "ಸಮಯ ಎಷ್ಟು",
            "ಈಗ ಸಮಯ ಎಷ್ಟು",
            "समय",
            "समय क्या है"
        ]

        if any(word in message_lower for word in time_words):

            current_time = datetime.now(
                ZoneInfo("Asia/Kolkata")
            ).strftime("%I:%M %p")

            return jsonify({
                "response":
                    f"The current time is {current_time}."
            })


        # ====================================================
        # DATE
        # ====================================================

        date_words = [
            "date",
            "today date",
            "today's date",
            "what is the date",
            "what's the date",
            "current date",
            "ಇಂದಿನ ದಿನಾಂಕ",
            "ದಿನಾಂಕ ಏನು",
            "आज की तारीख"
        ]

        if any(word in message_lower for word in date_words):

            current_date = datetime.now(
                ZoneInfo("Asia/Kolkata")
            ).strftime("%d %B %Y")

            return jsonify({
                "response":
                    f"Today's date is {current_date}."
            })


        # ====================================================
        # GEMINI
        # ====================================================

        models = [
            "gemini-3.6-flash",
            "gemini-3.5-flash-lite"
        ]

        last_error = None


        for model in models:

            for attempt in range(3):

                try:

                    print(
                        f"Trying {model}, "
                        f"attempt {attempt + 1}"
                    )

                    response = client.models.generate_content(
                        model=model,
                        contents=message
                    )

                    answer = response.text

                    if not answer:
                        answer = (
                            "I could not generate "
                            "a response."
                        )

                    print(
                        f"Gemini response received "
                        f"using {model}"
                    )

                    return jsonify({
                        "response": answer
                    })


                except Exception as e:

                    last_error = e

                    print(
                        f"{model} attempt "
                        f"{attempt + 1} failed:"
                    )

                    print(e)

                    if attempt < 2:
                        time.sleep(2)


        # ====================================================
        # GEMINI FAILED
        # ====================================================

        print("All Gemini attempts failed.")
        print(last_error)

        return jsonify({
            "response":
                "Gemini is temporarily unavailable. "
                "Please try again in a few seconds."
        }), 503


    except Exception as e:

        print("SERVER ERROR:")
        print(e)

        return jsonify({
            "response":
                "An error occurred on the AI server."
        }), 500


# ============================================================
# START SERVER
# ============================================================

if __name__ == "__main__":

    print("")
    print("==========================================")
    print("             NEXA AI BACKEND")
    print("==========================================")
    print("")
    print("Server starting...")
    print("")
    print("Laptop address:")
    print("http://10.86.68.123:5000")
    print("")
    print("Chat endpoint:")
    print("http://10.86.68.123:5000/chat")
    print("")
    print("Health check:")
    print("http://10.86.68.123:5000/health")
    print("")
    print("Keep this window OPEN while using NEXA.")
    print("==========================================")
    print("")

    app.run(
        host="0.0.0.0",
        port=5000,
        debug=True
    )