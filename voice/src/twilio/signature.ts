import { createHmac, timingSafeEqual } from "node:crypto";

// X-Twilio-Signature verification (Twilio docs, "Webhooks security"):
//   base64(HMAC-SHA1(authToken, fullUrl + concat(sorted POST params as key+value)))
export function computeSignature(authToken: string, url: string, params: Record<string, string>): string {
  const data = Object.keys(params)
    .sort()
    .reduce((acc, key) => acc + key + params[key], url);
  return createHmac("sha1", authToken).update(data, "utf8").digest("base64");
}

export function isValidSignature(
  authToken: string,
  url: string,
  params: Record<string, string>,
  signature: string | undefined,
): boolean {
  if (!signature) return false;
  const expected = Buffer.from(computeSignature(authToken, url, params));
  const given = Buffer.from(signature);
  return expected.length === given.length && timingSafeEqual(expected, given);
}
