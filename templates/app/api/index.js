const express = require("express");
const { Pool } = require("pg");

const app = express();
const port = process.env.PORT || 3000;

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
});

app.get("/health", async (_req, res) => {
  try {
    await pool.query("SELECT 1");
    res.json({ status: "healthy", db: "connected" });
  } catch {
    res.status(503).json({ status: "unhealthy", db: "disconnected" });
  }
});

app.get("/api/hello", async (_req, res) => {
  try {
    const result = await pool.query("SELECT NOW() as time");
    res.json({
      message: "Hello from homekase!",
      db_time: result.rows[0].time,
    });
  } catch {
    res.json({ message: "Hello from homekase!" });
  }
});

app.listen(port, () => {
  console.log(`API running on port ${port}`);
});
