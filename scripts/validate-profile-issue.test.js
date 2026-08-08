#!/usr/bin/env node

"use strict";

const assert = require("node:assert/strict");
const { inspectIssueBody } = require("./validate-profile-issue.js");

const validProfile = {
  id: "example-kit",
  name: "Example kit",
  description: "A validated example profile.",
  source: "General MIDI Level 1 percussion",
  target: "Example MPC program",
  gmRange: [35, 81],
  silentNote: 0,
  direct: { "36": 36, "38": 38 },
  fallback: { "39": 40 }
};

function fenced(profile) {
  return `Description\n\n\`\`\`profile-json\n${JSON.stringify(profile, null, 2)}\n\`\`\``;
}

assert.equal(inspectIssueBody(fenced(validProfile)).valid, true);

const overlap = structuredClone(validProfile);
overlap.fallback["36"] = 40;
assert.deepEqual(inspectIssueBody(fenced(overlap)), {
  valid: false,
  errors: ["direct and fallback must not map the same source note."]
});

assert.deepEqual(inspectIssueBody("No profile here."), {
  valid: false,
  errors: ["Provide exactly one fenced `profile-json` block."]
});

assert.deepEqual(inspectIssueBody(null), {
  valid: false,
  errors: ["Provide exactly one fenced `profile-json` block."]
});

assert.deepEqual(inspectIssueBody(`${fenced(validProfile)}\n\n${fenced(validProfile)}`), {
  valid: false,
  errors: ["Provide exactly one fenced `profile-json` block."]
});

assert.deepEqual(inspectIssueBody("```profile-json\n{ bad json }\n```"), {
  valid: false,
  errors: ["The `profile-json` block is not valid JSON."]
});

console.log("Profile issue validator tests passed.");
