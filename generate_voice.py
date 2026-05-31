"""
ArthaNote — Voiceover Generator
Run: pip install gtts
Then: python generate_voice.py
Output: arthanote_voiceover.mp3
"""
from gtts import gTTS

script = (
    "Still writing your shop accounts in a notebook? "
    "Wrong totals. Missing sales. Supplier confusion. "
    "Every single day. "
    "There's a smarter way. "
    "ArthaNote tracks every sale, expense and supplier payment automatically. "
    "Just scan your ledger photo. AI does the rest. "
    "Multi shop. Offline. Tamil and English. "
    "ArthaNote. Download free. Your wealth, noted."
)

print("Generating voiceover...")
tts = gTTS(text=script, lang='en', slow=False)
tts.save("arthanote_voiceover.mp3")
print("✅ Saved: arthanote_voiceover.mp3")
print("Duration: ~30 seconds")
