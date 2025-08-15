// File: server.js
const express = require("express");
const mongoose = require("mongoose");
const cors = require("cors");
const http = require("http");
const { Server } = require("socket.io");

const app = express();
const server = http.createServer(app);
const io = new Server(server, {
  cors: { origin: "*" }
});

app.use(express.json());
app.use(cors());

mongoose.connect("mongodb://localhost:27017/trafficDB");

const trafficSchema = new mongoose.Schema({
  location: String,
  latitude: Number,
  longitude: Number,
  vehicleCount: Number,
  traffic: String,
});
const Traffic = mongoose.model("Traffic", trafficSchema);

app.post("/update_traffic", async (req, res) => {
  const { location, vehicleCount, latitude, longitude } = req.body;
  const trafficStatus = vehicleCount > 10 ? "high" : "low";

  await Traffic.updateOne(
    { location },
    {
      $set: {
        vehicleCount,
        traffic: trafficStatus,
        latitude,
        longitude,
      },
    },
    { upsert: true }
  );

  io.emit("traffic_update", {
    location,
    latitude,
    longitude,
    traffic: trafficStatus,
    vehicleCount,
  });

  console.log(`📍 ${location} updated → 🚗 ${vehicleCount} → 🚦 ${trafficStatus}`);
  res.send({ success: true });
});

app.get("/traffic_status", async (req, res) => {
  const data = await Traffic.find({});
  res.send(data);
});

server.listen(5000, () => console.log("🚀 Server running on port 5000"));
