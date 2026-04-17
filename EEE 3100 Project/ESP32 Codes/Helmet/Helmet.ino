#include <WiFi.h>
#include <WebServer.h>
#include <Wire.h>
#include <LiquidCrystal_I2C.h>

const char* ssid = "ESP32_Server";
const char* password = "12345678";

WebServer server(80);

LiquidCrystal_I2C lcd(0x27, 16, 2);

#define MOTOR_PIN 12
#define BUZZER_PIN 4

bool waitingShown = false;

// -------- Buzzer Function --------
void beepBuzzer() {
  for (int i = 0; i < 10; i++) {
    digitalWrite(BUZZER_PIN, HIGH);
    delay(100);
    digitalWrite(BUZZER_PIN, LOW);
    delay(100);
  }
}

// -------- Engine ON --------
void engineON() {

  digitalWrite(MOTOR_PIN, HIGH);

  lcd.clear();
  lcd.setCursor(0, 0);
  lcd.print("Engine: ON");
}

// -------- Engine OFF --------
void engineOFF(String msg) {

  digitalWrite(MOTOR_PIN, LOW);

  lcd.clear();
  lcd.setCursor(0, 0);
  lcd.print("Engine: OFF");

  lcd.setCursor(0, 1);
  lcd.print(msg);

  beepBuzzer();

  delay(2000);
}

// -------- Handle URL --------
void handleData() {

  if (server.hasArg("value")) {

    String val = server.arg("value");

    Serial.println("Received value: " + val);

    if (val == "1") {
      engineOFF("Drowsiness");
    }

    else if (val == "2") {
      engineOFF("Alcohol");
    }

    else if (val == "3") {
      engineOFF("Fall Detect");
    }

    else if (val == "4") {
      engineON();
      lcd.setCursor(0, 1);
      lcd.print("Helmet Detected");
    }

    else if (val == "5") {
      digitalWrite(MOTOR_PIN, LOW);

      lcd.clear();
      lcd.setCursor(0, 0);
      lcd.print("Engine: OFF");
      lcd.setCursor(0, 1);
      lcd.print("No Helmet");

      delay(2000);
    }

    else if (val == "6") {
      digitalWrite(MOTOR_PIN, LOW);

      lcd.clear();
      lcd.setCursor(0, 0);
      lcd.print("Engine: OFF");
      lcd.setCursor(0, 1);
      lcd.print("Emergency");

      beepBuzzer();

      delay(2000);
    }

    server.send(200, "text/plain", "Data received: " + val);

  } else {
    server.send(400, "text/plain", "No value received");
  }
}

void setup() {

  Serial.begin(115200);

  pinMode(MOTOR_PIN, OUTPUT);
  pinMode(BUZZER_PIN, OUTPUT);

  lcd.begin();
  lcd.backlight();

  // Boot Message
  lcd.setCursor(0, 0);
  lcd.print("Starting...");
  delay(2000);

  // Start ESP32 Hotspot
  WiFi.softAP(ssid, password);

  lcd.clear();
  lcd.setCursor(0, 0);
  lcd.print("Bike Ready");

  Serial.print("Server IP: ");
  Serial.println(WiFi.softAPIP());

  delay(2000);



  server.on("/sendData", handleData);
  server.begin();

  Serial.println("HTTP server started");
}

void loop() {

  server.handleClient();

  int clients = WiFi.softAPgetStationNum();

  // No device connected
  if (clients == 0 && !waitingShown) {

    lcd.clear();
    lcd.setCursor(0, 0);
    lcd.print("Waiting for");
    lcd.setCursor(0, 1);
    lcd.print("Helmet");

    waitingShown = true;
  }

  // Device connected
  if (clients > 0 && waitingShown) {

    lcd.clear();
    lcd.setCursor(0, 0);
    lcd.print("Helmet");
    lcd.setCursor(0, 1);
    lcd.print("Connected");

    delay(2000);

    waitingShown = false;
  }
}