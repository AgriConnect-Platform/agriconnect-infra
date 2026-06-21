const https = require('https');
const http = require('http');

const ALB_URL = process.env.ALB_URL || '';

const WEATHER_MESSAGES = [
  { message: 'Heavy rainfall expected in the next 24 hours. Ensure proper drainage in your fields and protect harvested crops from moisture.', alert_type: 'rain' },
  { message: 'High temperature alert: temperatures expected to exceed 40°C. Increase irrigation frequency and provide shade for sensitive crops.', alert_type: 'heat' },
  { message: 'Strong winds forecast. Secure your greenhouse covers, support tall crops, and delay any spray applications until conditions improve.', alert_type: 'storm' },
  { message: 'Dry weather continues. Monitor soil moisture closely and schedule irrigation to prevent crop stress.', alert_type: 'default' },
];

function callNotificationService(payload) {
  return new Promise((resolve, reject) => {
    const body = JSON.stringify(payload);
    const protocol = ALB_URL.startsWith('https') ? https : http;
    const host = ALB_URL.replace(/^https?:\/\//, '');

    const options = {
      hostname: host,
      path: '/api/notifications/weather-alert',
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(body),
      },
      timeout: 30000,
    };

    const req = protocol.request(options, (res) => {
      let data = '';
      res.on('data', (chunk) => { data += chunk; });
      res.on('end', () => {
        console.log(`Notification service responded: ${res.statusCode} — ${data}`);
        resolve({ statusCode: res.statusCode, body: data });
      });
    });

    req.on('error', reject);
    req.on('timeout', () => req.destroy(new Error('Request timed out')));
    req.write(body);
    req.end();
  });
}

exports.handler = async (event) => {
  console.log('Weather alert scheduler triggered', JSON.stringify(event));

  if (!ALB_URL) {
    console.error('ALB_URL not configured — cannot reach notification service');
    return { statusCode: 500, body: 'ALB_URL not set' };
  }

  // Pick a message based on hour of day (rotates through alerts)
  const hour = new Date().getUTCHours();
  const alertData = WEATHER_MESSAGES[hour % WEATHER_MESSAGES.length];

  try {
    const result = await callNotificationService(alertData);
    console.log('Weather alert broadcast complete:', result);
    return { statusCode: 200, body: 'Weather alert sent to all farmers' };
  } catch (err) {
    console.error('Failed to broadcast weather alert:', err.message);
    throw err;
  }
};
