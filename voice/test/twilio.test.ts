import { test } from "node:test";
import assert from "node:assert/strict";
import { computeSignature, isValidSignature } from "../src/twilio/signature.js";
import { conversationRelay, dial, escapeXml } from "../src/twilio/twiml.js";

test("signature matches Twilio's documented example", () => {
  const url = "https://mycompany.com/myapp.php?foo=1&bar=2";
  const params = { CallSid: "CA1234567890ABCDE", Caller: "+12349013030", Digits: "1234", From: "+12349013030", To: "+18005551212" };
  assert.equal(computeSignature("12345", url, params), "0/KCTR6DLpKmkAf8muzZqo1nDgQ=");
  assert.ok(isValidSignature("12345", url, params, "0/KCTR6DLpKmkAf8muzZqo1nDgQ="));
  assert.ok(!isValidSignature("12345", url, params, "forged"));
  assert.ok(!isValidSignature("12345", url, params, undefined));
});

test("TwiML escapes every interpolated value", () => {
  assert.equal(escapeXml(`<a href="x">&'</a>`), "&lt;a href=&quot;x&quot;&gt;&amp;&apos;&lt;/a&gt;");
  const xml = conversationRelay({
    relayUrl: "wss://voice.example.com/twilio/relay",
    actionUrl: "https://voice.example.com/twilio/voice/relay-ended",
    welcomeGreeting: `Grüezi, "Taxi" & Co`,
    language: "de-DE",
    secondaryLanguage: "en-US",
    hints: ["Schaan", "Flughafen Zürich"],
    parameters: { tenantId: "7" },
  });
  assert.match(xml, /welcomeGreeting="Grüezi, &quot;Taxi&quot; &amp; Co"/);
  assert.match(xml, /<Language code="en-US"\/>/);
  assert.match(xml, /hints="Schaan,Flughafen Zürich"/);
  assert.match(xml, /<Parameter name="tenantId" value="7"\/>/);
  assert.doesNotMatch(xml, /ttsProvider=/); // unset options are left to Twilio's defaults
});

test("dial TwiML points no-answer handling at the core", () => {
  const xml = dial("+41791234567", "https://core.example.com/twilio/voice/dial_status");
  assert.match(xml, /<Dial timeout="25" action="https:\/\/core.example.com\/twilio\/voice\/dial_status"><Number>\+41791234567<\/Number><\/Dial>/);
});
