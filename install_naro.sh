#!/bin/bash

echo "[NARO] Installation gestartet..."

# Systempakete
sudo apt update
sudo apt install -y python3-pip python3-flask espeak-ng git unzip hostapd dnsmasq portaudio19-dev

# Python-Pakete
pip3 install flask pyttsx3 vosk sounddevice requests beautifulsoup4

# Ordnerstruktur
mkdir -p ~/naro_os/modules ~/naro_os/speech ~/naro_os/templates ~/naro_os/models
cd ~/naro_os

# Vosk-Sprachmodell (DE) laden
echo "[NARO] Lade Vosk-Modell..."
curl -L -o vosk-model.zip https://alphacephei.com/vosk/models/vosk-model-small-de-0.15.zip
unzip vosk-model.zip -d models && rm vosk-model.zip
mv models/vosk-model-small-de-0.15 models/de

# Hauptprogramm
cat <<EOF > main.py
from flask import Flask, request, render_template
from modules import calendar_module, notes_module, research_module
from speech.speak import speak
from speech.listen import listen
import os
import threading

app = Flask(__name__)
language = "de"
response = ""

def start_listening():
    global response, language
    while True:
        user_input = listen()
        if user_input:
            if "englisch" in user_input:
                language = "en"
                response = "Okay, I will now speak English."
            elif "deutsch" in user_input:
                language = "de"
                response = "Alles klar, ich spreche wieder Deutsch."
            elif "termin" in user_input:
                response = calendar_module.handle(user_input)
            elif "merk" in user_input:
                response = notes_module.handle(user_input)
            elif "recherchiere" in user_input:
                response = research_module.handle(user_input)
            else:
                response = f"Ich habe '\{user_input}' gehört, aber weiß nicht, was ich tun soll."
            speak(response, language)

@app.route("/", methods=["GET", "POST"])
def home():
    global response
    if request.method == "POST":
        user_input = request.form["user_input"]
        response = f"Du hast gesagt: {user_input}"
        speak(response)
    return render_template("index.html", response=response)

if __name__ == "__main__":
    threading.Thread(target=start_listening, daemon=True).start()
    app.run(host="0.0.0.0", port=5000)
EOF

# HTML-Weboberfläche
cat <<EOF > templates/index.html
<!DOCTYPE html>
<html>
<head><title>Naro OS</title></head>
<body>
    <h1>Naro OS</h1>
    <form method="POST">
        <input type="text" name="user_input" placeholder="Sag was..." />
        <button type="submit">Senden</button>
    </form>
    {% if response %}
        <p><strong>Naro:</strong> {{ response }}</p>
    {% endif %}
</body>
</html>
EOF

# Notizenmodul
cat <<EOF > modules/notes_module.py
notes = []
def handle(text):
    if "zeig" in text:
        return "Gemerkte Notizen: " + ", ".join(notes) if notes else "Noch nichts gespeichert."
    else:
        notes.append(text)
        return "Ich habe das gespeichert."
EOF

# Kalendermodul
cat <<EOF > modules/calendar_module.py
def handle(text):
    return "Kalenderfunktion erkannt – später erweiterbar."
EOF

# Verbindungstest
cat <<EOF > modules/connection_check.py
import socket
def is_connected():
    try:
        socket.create_connection(("8.8.8.8", 53), timeout=2)
        return True
    except OSError:
        return False
EOF

# Recherchemodul
cat <<EOF > modules/research_module.py
import requests
from bs4 import BeautifulSoup
from modules.connection_check import is_connected

def handle(text):
    if not is_connected():
        return "Ich habe keine Internetverbindung."

    topic = text.lower().split("recherchiere mal über")[-1].strip()
    if not topic:
        return "Worüber soll ich recherchieren?"

    try:
        url = f"https://de.wikipedia.org/wiki/{topic.replace(' ', '_')}"
        headers = {"User-Agent": "Mozilla/5.0"}
        r = requests.get(url, headers=headers)
        soup = BeautifulSoup(r.text, "html.parser")
        p = soup.find("p")
        return p.text.strip() if p else "Kein guter Treffer gefunden."
    except:
        return "Fehler bei der Recherche."
EOF

# Sprachausgabe
cat <<EOF > speech/speak.py
import pyttsx3
def speak(text, lang="de"):
    engine = pyttsx3.init()
    engine.setProperty("rate", 160)
    engine.say(text)
    engine.runAndWait()
EOF

# Spracheingabe
cat <<EOF > speech/listen.py
import sounddevice as sd
import queue
import vosk
import json
import os

q = queue.Queue()
model_path = os.path.join(os.path.dirname(__file__), "..", "models", "de")
model = vosk.Model(model_path)

def callback(indata, frames, time, status):
    if status:
        print(status)
    q.put(bytes(indata))

def listen():
    with sd.RawInputStream(samplerate=16000, blocksize=8000, dtype='int16',
                           channels=1, callback=callback):
        rec = vosk.KaldiRecognizer(model, 16000)
        print("[NARO] Sprich jetzt...")
        while True:
            data = q.get()
            if rec.AcceptWaveform(data):
                result = json.loads(rec.Result())
                text = result.get("text", "").strip()
                if text:
                    print(f"[NARO] Gehört: {text}")
                    return text
EOF

# Autostart via crontab
(crontab -l 2>/dev/null; echo "@reboot python3 /home/pi/naro_os/main.py") | crontab -

echo "[NARO] Installation abgeschlossen. Starte mit:"
echo "   python3 ~/naro_os/main.py"
echo "Oder einfach: Reboot – Naro startet automatisch."
