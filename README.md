# Personal Life Management Application

A mobile application that helps users manage daily tasks, nutrient tracking, goal progress, calendar events, and diary entries.  
This project consists of:
- **Backend**: Python (Flask) REST API + MySQL database
- **Frontend**: Flutter (Dart) mobile app

---

## Folder Structure

backend/
  app.py
  db_config.py
  mobile.sql
  requirements.txt
  myenv/ (optional existing venv)

front-end/
  lib/
  assets/
  pubspec.yaml

---

## Prerequisites

### Backend
- Python 3.10+ installed
- MySQL Server installed and running
- (Optional) VS Code / any terminal

### Frontend
- Flutter SDK installed (3.x recommended)
- Android Studio installed (for emulator)
- An Android emulator OR real Android phone with USB debugging

---

## Backend Installation & Run

1) **Go to backend folder**
   cd backend

2) **Create a virtual environment (choose ONE option)**

   **Option A: Use the provided venv**
   - If you already have `myenv/` in the backend folder:
     - Windows:
       myenv\\Scripts\\activate
     - macOS/Linux:
       source myenv/bin/activate

   **Option B: Create your own venv**
   - Windows:
     python -m venv myenv
     myenv\\Scripts\\activate
   - macOS/Linux:
     python3 -m venv myenv
     source myenv/bin/activate

3) **Install backend dependencies**
   pip install -r requirements.txt

4) **Create database**
   - Open MySQL Workbench (or terminal)
   - Run this SQL file:
     backend/mobile.sql
   - It will create database `mobile` and all required tables.

5) **Configure DB connection**
   - Open:
     backend/db_config.py
   - Set your MySQL username, password, host, and port.

6) **Run backend server**
   python app.py

   The backend will start at:
   http://127.0.0.1:5000

---

## Frontend Installation & Run

1) **Go to front-end folder**
   cd front-end

2) **Install Flutter dependencies**
   flutter pub get

3) **Run the app**
   - Start Android Studio Emulator first
     (Device Manager → Run a device)
   - Then run:
     flutter run

   If using a real phone, plug it in and allow USB debugging, then:
   flutter run

---

## Notes / Troubleshooting

- If Flutter cannot connect to backend on emulator:
  - Use `10.0.2.2:5000` instead of `127.0.0.1:5000` in your API base URL.
- If MySQL tables already exist and you want a clean setup:
  - Re-run `mobile.sql` after dropping the database.
- If dependencies install fails:
  - Ensure your venv is activated before running pip.

---
