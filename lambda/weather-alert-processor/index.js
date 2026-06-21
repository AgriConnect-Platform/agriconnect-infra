const { SNSClient, PublishCommand } = require("@aws-sdk/client-sns");

const sns = new SNSClient({});

exports.handler = async (event) => {
  console.log("Weather alert processor triggered", JSON.stringify(event));

  try {
    await sns.send(new PublishCommand({
      TopicArn: process.env.SNS_TOPIC_ARN,
      Subject: "AgriConnect Weather Alert",
      Message: JSON.stringify({
        source: "weather-alert-processor",
        timestamp: new Date().toISOString(),
        event,
      }),
    }));

    return { statusCode: 200, body: "Alert sent" };
  } catch (err) {
    console.error("Failed to publish alert", err);
    throw err;
  }
};
