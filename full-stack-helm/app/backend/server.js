const express = require("express");
const mongoose = require("mongoose");

const app = express();

app.use(express.json());

// ==========================================
// CONFIGMAP VALUES
// ==========================================

const APP_NAME = process.env.APP_NAME;
const APP_ENV = process.env.APP_ENV;
const BACKEND_PORT = process.env.BACKEND_PORT;

// ==========================================
// SECRET VALUES
// ==========================================

const MONGO_USERNAME = process.env.MONGO_USERNAME;
const MONGO_PASSWORD = process.env.MONGO_PASSWORD;

// ==========================================
// DATABASE CONNECTION
// ==========================================

const mongoHost = process.env.MONGO_HOST || "mongodb";

const mongoUri =
  `mongodb://${MONGO_USERNAME}:${MONGO_PASSWORD}` +
  `@${mongoHost}:27017/demo?authSource=admin`;

console.log("Application:", APP_NAME);
console.log("Environment:", APP_ENV);
console.log("Backend Port:", BACKEND_PORT);

mongoose
  .connect(mongoUri)
  .then(() => {
    console.log("MongoDB connected");
  })
  .catch((error) => {
    console.error("MongoDB connection failed:", error.message);
  });

  app.use((req, res, next) => {
  console.log(`[${new Date().toISOString()}] ${req.method} ${req.url}`);
  next();
});

// ==========================================
// ROUTES
// ==========================================

app.get("/", (req, res) => {
  res.json({
    message: "Backend is running",
    application: APP_NAME,
    environment: APP_ENV
  });
});

app.get("/api/config", (req, res) => {
  res.json({
    appName: APP_NAME,
    environment: APP_ENV,
    port: BACKEND_PORT
  });
});

app.get("/api/health", (req, res) => {
  console.log(`[${new Date().toISOString()}] GET /api/health - status: healthy`);
  res.json({
    status: "healthy"
  });
});

app.listen(BACKEND_PORT, () => {
  console.log(`Backend listening on port ${BACKEND_PORT}`);
});