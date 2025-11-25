#include <WiFi.h>
#include <WebServer.h>
#include <DHT.h>
#include <TinyGPSPlus.h>
#include <HardwareSerial.h>

// === Wi-Fi Credentials ===
const char* ssid = "LORENZO FAMILY 2.4G";
const char* password = "08201979";

// === Pin Configuration ===
#define DHTPIN 21
#define DHTTYPE DHT11
const int mq2Pin = 32;
const int flamePin = 33;
const int buzzerPin = 25;  

// === GPS and GSM Pins ===
#define GPS_RX 13
#define GPS_TX 15
#define SIM800_TX 17
#define SIM800_RX 16

// === Objects ===
DHT dht(DHTPIN, DHTTYPE);
TinyGPSPlus gps;
HardwareSerial SerialGPS(2);
HardwareSerial sim800(1);
WebServer server(80);

// === Variables ===
float lastLat = 0.0;
float lastLon = 0.0;
unsigned long lastPrint = 0;
const unsigned long printInterval = 2000;
bool pauseMode = false;
String simCredit = "Unknown";

// === security of webserver ===
const char* webUser = "admin";    
const char* webPass = "ESP23pass";

// === Helper Functions ===
bool sendSMS(String number, String message) {
  Serial.println("📩 Sending SMS...");
  Serial.print("Message: ");
  Serial.println(message);

  // Flush serial
  while (sim800.available()) sim800.read();

  sim800.println("AT+CMGF=1");
  delay(1000);
  if (!sim800.find("OK")) {
    Serial.println("❌ Failed to set SMS mode");
    return false;
  }

  sim800.println("AT+CSCA=\"+639170000100\"");
  delay(1000);
  if (!sim800.find("OK")) {
    Serial.println("⚠️ SMSC set failed, continuing...");
  }

  sim800.print("AT+CMGS=\"");
  sim800.print(number);
  sim800.println("\"");
  delay(1000);
  if (!sim800.find(">")) {
    Serial.println("❌ Failed to get SMS prompt");
    return false;
  }

  sim800.print(message);
  sim800.write(26);
  delay(5000);

  String response = "";
  while (sim800.available()) {
    char c = sim800.read();
    response += c;
  }

  Serial.println("GSM Response after send:");
  Serial.println(response);

  if (response.indexOf("+CMGS") != -1) {
    Serial.println("✅ SMS sent successfully!");
    float currentBalance = simCredit.toFloat();
    if (currentBalance > 0) {
      simCredit = String(currentBalance - 1.0, 1);
      Serial.print("📱 Updated SIM Credit after SMS: ");
      Serial.println(simCredit);
    }
    return true;
  } else if (response.indexOf("+CMS ERROR") != -1) {
    Serial.println("❌ SMS error from network");
    return false;
  } else {
    Serial.println("❌ SMS send failed (no +CMGS response)");
    return false;
  }
}

void checkSimCredit() {
  Serial.println("💰 Checking SIM credit...");
  sim800.println("AT+CUSD=1,\"*143#\"");  
  delay(5000);

  String response = "";
  while (sim800.available()) {
    char c = sim800.read();
    response += c;
  }

  Serial.println("USSD Response: " + response);  

  if (response.indexOf("+CUSD: 1") != -1 && response.indexOf("BAL") != -1) {  
    int start = response.indexOf("BAL");
    if (start != -1) {
      start += 4;  
      int end = start;
      while (end < response.length() && (response[end] >= '0' && response[end] <= '9' || response[end] == '.')) {
        end++;  
      }
      simCredit = response.substring(start, end);  
    } else {
      simCredit = "Parsing failed";
    }
  } else if (response.indexOf("+CUSD: 2") != -1) {
    simCredit = "USSD Cancelled/Rejected";
  } else {
    simCredit = "No balance info";
  }

  Serial.print("📱 SIM Credit: ");
  Serial.println(simCredit);
}

// === Web Handlers ===
void handleSensorData() {
  float temp = dht.readTemperature();
  float hum = dht.readHumidity();
  int smoke = digitalRead(mq2Pin);
  int flame = digitalRead(flamePin);

  String simNumber = "09456453820";

  String json = "{";
  json += "\"temperature\":" + String(temp, 1) + ",";
  json += "\"humidity\":" + String(hum, 1) + ",";
  json += "\"smoke\":\"" + String(smoke == LOW ? "DETECTED" : "NONE") + "\",";
  json += "\"flame\":\"" + String(flame == LOW ? "DETECTED" : "NONE") + "\",";
  json += "\"latitude\":" + String(lastLat, 6) + ",";
  json += "\"longitude\":" + String(lastLon, 6) + ",";
  json += "\"sim_credit\":\"" + simCredit + "\",";
  json += "\"sim_number\":\"" + simNumber + "\",";  
  json += "\"sim_provider\":\"Globe\"";  
  json += "}";

server.sendHeader("Cache-Control", "no-cache, no-store, must-revalidate");
server.send(200, "application/json", json);
  Serial.println("📤 JSON Sent: " + json);
}

void handleCheckCredit() {
  checkSimCredit();
  String json = "{";
  json += "\"sim_credit\":\"" + simCredit + "\"";
  json += "}";
server.sendHeader("Cache-Control", "no-cache, no-store, must-revalidate");
server.send(200, "application/json", json);
  Serial.println("📤 Credit check triggered: " + json);
}

// === SETUP ===
void setup() {
  Serial.begin(115200);
  dht.begin();
  pinMode(mq2Pin, INPUT);
  pinMode(flamePin, INPUT);
  pinMode(buzzerPin, OUTPUT);
  digitalWrite(buzzerPin, LOW);

  SerialGPS.begin(9600, SERIAL_8N1, GPS_RX, GPS_TX);
  sim800.begin(115200, SERIAL_8N1, SIM800_RX, SIM800_TX);
  delay(3000);
  Serial.println("📶 Initializing SIM800L...");

  bool registered = false;
  unsigned long startTime = millis();
  const unsigned long timeout = 30000;
  while (!registered && millis() - startTime < timeout) {
    sim800.println("AT+CREG?");
    delay(1000);
    while (sim800.available()) {
      String resp = sim800.readString();
      Serial.println(resp);
      if (resp.indexOf("+CREG: 0,1") != -1 || resp.indexOf("+CREG: 0,5") != -1) {
        registered = true;
      }
    }
    if (!registered) {
      Serial.println("📡 Waiting for GSM network...");
      delay(2000);
    }
  }

  if (registered) {
    Serial.println("✅ GSM Network Registered!");
    checkSimCredit();
    if (sendSMS("+639758488578", "SIM800L SUCCESSFULLY CONNECTED TO THE ESP32")) {
      Serial.println("✅ Test SMS Sent Successfully!");
    } else {
      Serial.println("❌ Test SMS Failed! Check plan or carrier.");
    }
  } else {
    Serial.println("❌ GSM Registration Failed! Continuing without GSM...");
    simCredit = "GSM Failed";
  }

  Serial.println("Connecting to WiFi...");
  WiFi.begin(ssid, password);
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println("Connecting to WiFi...");
  WiFi.begin(ssid, password);
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }

  Serial.println("✅ WiFi Connected!");
  Serial.print("📶 IP: ");
  Serial.println(WiFi.localIP());

  server.on("/data", []() {                               
    if (!server.authenticate(webUser, webPass)) {
      return server.requestAuthentication();
    }
    handleSensorData();
  });

  server.on("/checkcredit", []() {                         
    if (!server.authenticate(webUser, webPass)) {
      return server.requestAuthentication();
    }
    handleCheckCredit();
  });

  server.begin();
  Serial.println("🌐 Web Server started!");
}

// === LOOP ===
void loop() {
  if (!pauseMode) {
    while (SerialGPS.available()) gps.encode(SerialGPS.read());
    if (gps.location.isValid()) {
      lastLat = gps.location.lat();
      lastLon = gps.location.lng();
    }
  }

  if (!pauseMode) {
    server.handleClient();
  }

  float temp = 0.0;
  float hum = 0.0;
  int smoke = HIGH;
  int flame = digitalRead(flamePin);

  if (!pauseMode) {
    temp = dht.readTemperature();
    hum = dht.readHumidity();
    smoke = digitalRead(mq2Pin);
  }

  if (flame == LOW || smoke == LOW) {
    digitalWrite(buzzerPin, HIGH);
  } else {
    digitalWrite(buzzerPin, LOW);
  }

  if (!pauseMode && millis() - lastPrint > printInterval) {
    lastPrint = millis();
    Serial.println("================================");
    Serial.print("🌡 Temperature: "); Serial.println(temp);
    Serial.print("💧 Humidity: "); Serial.println(hum);
    Serial.print("🔥 Flame: "); Serial.println(flame == LOW ? "DETECTED" : "NONE");
    Serial.print("💨 Smoke: "); Serial.println(smoke == LOW ? "DETECTED" : "NONE");
    Serial.print("📍 Latitude: "); Serial.println(lastLat, 6);
    Serial.print("📍 Longitude: "); Serial.println(lastLon, 6);
    Serial.print("📱 SIM Credit: "); Serial.println(simCredit);
    Serial.println("================================");
  }

  static bool smsSent = false;
  if (flame == LOW) {
    if (!smsSent) {
      smsSent = true;
      pauseMode = true;
      Serial.println("🚨 Fire detected! Entering pause mode for SMS...");
      String msg = "Emergency warning: Fire detected, leave the area now! Temp: " + String(temp, 1) + "C, Lat: " + String(lastLat, 6) + ", Lon: " + String(lastLon, 6);
      if (sendSMS("+639758488578", msg)) {
        Serial.println("✅ SMS sent! Exiting pause mode.");
      } else {
        Serial.println("❌ SMS failed! Exiting pause mode anyway.");
      }
      pauseMode = false;
    }
  } else {
    smsSent = false;
  }
}
