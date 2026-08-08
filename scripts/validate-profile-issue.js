#!/usr/bin/env node

"use strict";

const fs = require("node:fs");

const COMMENT_MARKER = "<!-- mpc-midi-converter-profile-validation -->";
const REQUIRED_KEYS = [
  "id",
  "name",
  "description",
  "source",
  "target",
  "gmRange",
  "silentNote",
  "direct",
  "fallback"
];
const REQUIRED_KEY_SET = new Set(REQUIRED_KEYS);

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function isMIDIByte(value) {
  return Number.isInteger(value) && value >= 0 && value <= 127;
}

function extractProfileBlocks(body) {
  const text = typeof body === "string" ? body : "";
  const pattern = /^```profile-json[ \t]*\r?\n([\s\S]*?)^```[ \t]*$/gm;
  return [...text.matchAll(pattern)].map((match) => match[1]);
}

function validateMappingObject(value, name, lower, upper, errors) {
  if (!isPlainObject(value)) {
    errors.push(`${name} must be an object whose keys are GM note numbers.`);
    return new Set();
  }

  const notes = new Set();
  for (const [rawSource, target] of Object.entries(value)) {
    if (!/^(0|[1-9][0-9]{0,2})$/.test(rawSource)) {
      errors.push(`${name} contains a source note that is not a decimal MIDI number.`);
      continue;
    }
    const source = Number(rawSource);
    if (!isMIDIByte(source) || source < lower || source > upper) {
      errors.push(`${name} contains a source note outside gmRange.`);
    }
    if (!isMIDIByte(target)) {
      errors.push(`${name} contains a target that is not a MIDI note from 0 through 127.`);
    }
    notes.add(source);
  }
  return notes;
}

function validateProfile(profile) {
  const errors = [];
  if (!isPlainObject(profile)) {
    return ["The profile JSON must be an object."];
  }

  const keys = Object.keys(profile);
  if (keys.length !== REQUIRED_KEYS.length || keys.some((key) => !REQUIRED_KEY_SET.has(key))) {
    errors.push("The profile must contain exactly the documented profile fields.");
  }
  for (const key of REQUIRED_KEYS) {
    if (!Object.hasOwn(profile, key)) {
      errors.push("The profile is missing one or more required fields.");
      break;
    }
  }
  for (const key of ["id", "name", "description", "source", "target"]) {
    if (typeof profile[key] !== "string" || profile[key].trim().length === 0) {
      errors.push("Identity and description fields must be non-empty strings.");
      break;
    }
  }

  let lower = 0;
  let upper = 127;
  if (!Array.isArray(profile.gmRange) || profile.gmRange.length !== 2
      || !isMIDIByte(profile.gmRange[0]) || !isMIDIByte(profile.gmRange[1])
      || profile.gmRange[0] > profile.gmRange[1]) {
    errors.push("gmRange must contain two ascending MIDI notes from 0 through 127.");
  } else {
    [lower, upper] = profile.gmRange;
  }
  if (!isMIDIByte(profile.silentNote)) {
    errors.push("silentNote must be a MIDI note from 0 through 127.");
  }

  const direct = validateMappingObject(profile.direct, "direct", lower, upper, errors);
  const fallback = validateMappingObject(profile.fallback, "fallback", lower, upper, errors);
  if ([...direct].some((note) => fallback.has(note))) {
    errors.push("direct and fallback must not map the same source note.");
  }

  return [...new Set(errors)];
}

function inspectIssueBody(body) {
  const blocks = extractProfileBlocks(body);
  if (blocks.length !== 1) {
    return {
      valid: false,
      errors: ["Provide exactly one fenced `profile-json` block."],
    };
  }

  let profile;
  try {
    profile = JSON.parse(blocks[0]);
  } catch {
    return {
      valid: false,
      errors: ["The `profile-json` block is not valid JSON."],
    };
  }

  const errors = validateProfile(profile);
  return { valid: errors.length === 0, errors };
}

function renderComment(result) {
  if (result.valid) {
    return `${COMMENT_MARKER}\n## Profile validation\n\n✅ The profile JSON has one valid block and passes schema, MIDI range, and direct/fallback-overlap checks.`;
  }
  return `${COMMENT_MARKER}\n## Profile validation\n\n❌ The profile cannot be accepted yet.\n\n${result.errors.map((error) => `- ${error}`).join("\n")}`;
}

async function githubRequest(apiURL, token, path, options = {}) {
  const response = await fetch(`${apiURL}${path}`, {
    method: options.method || "GET",
    headers: {
      Accept: "application/vnd.github+json",
      Authorization: `Bearer ${token}`,
      "X-GitHub-Api-Version": "2022-11-28",
      ...(options.body ? { "Content-Type": "application/json" } : {})
    },
    body: options.body ? JSON.stringify(options.body) : undefined
  });
  if (!response.ok) {
    throw new Error(`GitHub API request failed with status ${response.status}.`);
  }
  return response.status === 204 ? undefined : response.json();
}

async function listIssueComments(apiURL, token, repository, issueNumber) {
  const comments = [];
  for (let page = 1; ; page += 1) {
    const batch = await githubRequest(
      apiURL,
      token,
      `/repos/${repository}/issues/${issueNumber}/comments?per_page=100&page=${page}`
    );
    comments.push(...batch);
    if (batch.length < 100) {
      return comments;
    }
  }
}

async function upsertComment(apiURL, token, repository, issueNumber, body) {
  const comments = await listIssueComments(apiURL, token, repository, issueNumber);
  const ownComments = comments.filter((comment) =>
    comment.user?.login === "github-actions[bot]"
      && typeof comment.body === "string"
      && comment.body.includes(COMMENT_MARKER)
  );

  if (ownComments.length === 0) {
    await githubRequest(apiURL, token, `/repos/${repository}/issues/${issueNumber}/comments`, {
      method: "POST",
      body: { body }
    });
    return;
  }

  const [primary, ...duplicates] = ownComments;
  await githubRequest(apiURL, token, `/repos/${repository}/issues/comments/${primary.id}`, {
    method: "PATCH",
    body: { body }
  });
  for (const comment of duplicates) {
    await githubRequest(apiURL, token, `/repos/${repository}/issues/comments/${comment.id}`, {
      method: "DELETE"
    });
  }
}

async function main() {
  const eventPath = process.argv[2];
  if (!eventPath) {
    throw new Error("Usage: validate-profile-issue.js <GitHub event JSON path>");
  }
  const event = JSON.parse(fs.readFileSync(eventPath, "utf8"));
  const issue = event.issue;
  if (!issue || !Number.isInteger(issue.number)) {
    throw new Error("The event does not contain a valid issue payload.");
  }
  const token = process.env.GITHUB_TOKEN;
  const repository = process.env.GITHUB_REPOSITORY;
  const apiURL = process.env.GITHUB_API_URL || "https://api.github.com";
  if (!token || !repository) {
    throw new Error("GITHUB_TOKEN and GITHUB_REPOSITORY are required.");
  }

  const result = inspectIssueBody(typeof issue.body === "string" ? issue.body : "");
  await upsertComment(apiURL, token, repository, issue.number, renderComment(result));
}

module.exports = {
  COMMENT_MARKER,
  extractProfileBlocks,
  inspectIssueBody,
  validateProfile,
};

if (require.main === module) {
  main().catch((error) => {
    console.error(error.message);
    process.exitCode = 1;
  });
}
