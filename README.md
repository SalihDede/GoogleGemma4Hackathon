# LUMOS

**Enlight Your World**

LUMOS is a mobile AI assistant designed to help blind and low-vision users understand their surroundings, act more independently, and stay safer in everyday situations. It combines an accessible Flutter app, on-device Gemma inference, cloud fallback, camera understanding, voice interaction, device tools, and optional ESP32-based sensor context.

The goal is simple: a user should be able to ask natural questions like "What is in front of me?", "Read this text", "Where is the door?", "Call my mom", or "Is it dark here?" and receive a short, spoken, practical answer.

## Download Demo APK

You can try the Android build here:

[Download LUMOS APK](https://drive.google.com/file/d/1JkmT24YhbLoFWN2OSwZIKxdYIFYbF-dH/view?usp=sharing)

## Why LUMOS Matters

Many accessibility tools solve one narrow problem: OCR, object detection, navigation, or voice commands. Real daily life is messier. A blind user may need to read a sign, check if a bag is open, understand whether a path is blocked, call a contact, set a reminder, or decide whether a camera image is reliable in poor lighting.

LUMOS treats these needs as one continuous assistant experience:

- It can talk and listen.
- It can use the camera when visual evidence is needed.
- It can call tools for contacts, calls, reminders, date, time, sensors, and scene capture.
- It can use cloud AI when internet is available.
- It can fall back to a local Gemma LiteRT model when internet is unavailable.

## Core Features

### Accessible Conversational Assistant

- Voice-first interaction with speech recognition and text-to-speech.
- Uses the phone's native STT and TTS engines instead of running separate speech models inside the app.
- This keeps voice input/output fast and practical while reducing RAM pressure, leaving more memory available for the local LLM.
- Speech input and output follow the system language configured in the phone settings, which pairs naturally with Gemma 4's multilingual capabilities.
- Chat UI designed for short, readable, streamable responses.
- Wake phrase support for hands-free use.
- Responses are shaped for spoken guidance, not long visual reading.

### Hybrid AI: Cloud + Offline

- Uses OpenRouter cloud inference when internet and an API key are available.
- Uses an on-device Gemma 4 E2B LiteRT-LM model for offline operation.
- Downloads the local model during setup before allowing the user into the main app.
- If internet drops during a conversation, LUMOS activates the installed local model and continues offline.
- Hugging Face token and OpenRouter API key are entered and updated from the app UI.

### On-Device Gemma LiteRT

- Model: `litert-community/gemma-4-E2B-it-litert-lm`
- File: `gemma-4-E2B-it.litertlm`
- Runtime: `flutter_gemma`
- Backend preference support: Auto, GPU, CPU, and NPU fallback paths.
- Local model activation is handled even when the model was already downloaded, so offline fallback can work without a fresh network download.

### Vision and Navigation Guidance

LUMOS uses camera images to provide accessible navigation and descriptions:

- Scene description: "Computer on the table's right, phone on the left."
- Text reading: Reading labels and text with high confidence.
- Object search: "Door on the right side, approximately three steps ahead."
- **Clock-face positioning**: "Window at 10 o'clock, door at 3 o'clock."
- **Body-anchored navigation**: Natural, user-centric phrases like "Two steps ahead and to your right is the stairs."

No map APIs or GPS are used. All navigation is provided through image analysis and natural language only, delivering more practical, speech-friendly, and safer guidance for visually impaired users.

### Tool-Using Assistant

The assistant can call real device and environment tools instead of guessing.

Implemented tool categories include:

- Scene and camera tools: `capture_image`, `describe_scene`, `read_text`, `identify_object`
- Sensor tools: `check_sensor_context`, `measure_brightness`, `get_environment_status`, `detect_motion_state`, `read_inertial_sensors`
- Phone and productivity tools: `search_contact`, `make_call`, `set_reminder`, `cancel_action`
- Utility tools: `get_date`, `get_time`

### ESP32 Sensor Extension

The repository includes an ESP32 sensor module area for hardware-assisted context. The planned and partially integrated sensor flow is:

```text
External sensors
    |
    v
ESP32 firmware
    |
    v
Flutter SensorHubService
    |
    v
ToolRunner
    |
    v
LUMOS response
```

Sensor-oriented use cases include:

- Ambient brightness and camera reliability.
- Temperature, humidity, pressure, and comfort status.
- Motion, tilt, shaking, impact, or stability before taking a photo.
- Future proactive safety alerts from hardware-level events.

## Example User Scenarios

- "LUMOS, what is in front of me?"
- "Read the text on this paper."
- "Where is the exit?"
- "Is my bag open?"
- "Is this place dark?"
- "Am I holding the phone steady?"
- "Call my mom."
- "Remind me to take my medicine in ten minutes."

LUMOS is built to answer these with direct, accessible, action-oriented language.

## Repository Structure

```text
GoogleCompetitionUnsloth/
  gallery_assistant/        Flutter mobile app
  ESP32_Sensors/            ESP32 firmware, hardware notes, inventory
  finetunedModelToLiteRT/   Gemma fine-tuning and LiteRT conversion notebooks
  sysPrompts/               System prompt drafts in English and Turkish
  .github/                  Project automation/support files
```

Important app paths:

```text
gallery_assistant/lib/main.dart
gallery_assistant/lib/screens/setup_screen.dart
gallery_assistant/lib/screens/chat_screen.dart
gallery_assistant/lib/providers/chat_provider.dart
gallery_assistant/lib/services/inference_router.dart
gallery_assistant/lib/services/litert_service.dart
gallery_assistant/lib/services/cloud_inference_service.dart
gallery_assistant/lib/services/model_manager_service.dart
gallery_assistant/lib/services/tool_runner.dart
gallery_assistant/lib/services/sensor_hub_service.dart
```

## Architecture

```text
User voice/text/image request
    |
    v
Native phone STT/TTS + Flutter UI
    |
    v
ChatProvider
    |
    v
InferenceRouter
    |------------------------------|
    v                              v
OpenRouter cloud model       Local Gemma LiteRT model
    |                              |
    |--------------|---------------|
                   v
              ToolRunner
                   |
                   v
Camera, sensors, contacts, calls, reminders, date/time
                   |
                   v
Accessible final response
```

## Setup for Development

### Requirements

- Flutter SDK
- Android Studio / Android SDK
- A physical Android device is recommended for camera, microphone, contacts, TTS, and local model testing.
- Optional Hugging Face token for model download.
- Optional OpenRouter API key for cloud mode.

### Install Dependencies

```bash
cd gallery_assistant
flutter pub get
```

### Run

```bash
flutter run
```

### First Launch

On first launch, the app asks for:

- Hugging Face token: optional for public model downloads.
- OpenRouter API key: required only for cloud mode.

The app downloads the offline model before entering the main chat experience. This ensures the assistant can still work when the user loses internet access later.

## Model Pipeline

The project includes notebooks for fine-tuning and converting Gemma models:

- `finetunedModelToLiteRT/Unsloth_Gemma4_E2B_Finetune.ipynb`
- `finetunedModelToLiteRT/Google_Gemma4_E2B_To_LiteRT_LM_v2.ipynb`
- `finetunedModelToLiteRT/Google_Finetuned_Gemma4_E2B_To_LiteRT_LM_v2.ipynb`

The mobile app currently downloads and runs the LiteRT-LM Gemma model through `flutter_gemma`.

## Privacy and Safety

LUMOS is designed for sensitive accessibility contexts, so it follows conservative behavior:

- It does not invent phone numbers; it searches device contacts.
- It asks for confirmation before initiating a call.
- It avoids pretending to know high-risk details such as medicine, money, allergens, or expiry dates without evidence.
- It uses tools for current time, date, sensor data, and camera evidence instead of guessing.
- It warns the user when a situation may be uncertain or unsafe.

## Built With

- Flutter
- Riverpod
- flutter_gemma
- Gemma 4 E2B LiteRT-LM
- OpenRouter API
- `speech_to_text` using the phone's native speech recognition
- `flutter_tts` using the phone's native text-to-speech engine
- flutter_contacts
- ESP32-CAM and ESP32 sensor expansion

## Competition Summary

LUMOS demonstrates how Gemini/Gemma-style AI can move beyond chat and become an accessibility agent connected to real mobile and hardware capabilities. It combines cloud intelligence, offline resilience, tool use, voice interaction, camera understanding, and sensor context in one assistant for blind and low-vision users.

The core idea is not just to answer questions, but to help users act in the physical world with more confidence.
