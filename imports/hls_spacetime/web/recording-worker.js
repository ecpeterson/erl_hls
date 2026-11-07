import { prepareRecording } from "./recording-model.js";

/** One worker owns one recording load; termination cancels all remaining work. */
self.onmessage = ({ data }) => {
  try {
    self.postMessage({ result: prepareRecording(data) });
  } catch (error) {
    self.postMessage({ error: error.message });
  }
};
