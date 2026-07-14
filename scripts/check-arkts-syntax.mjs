import fs from 'node:fs';
import path from 'node:path';

function listEtsFiles(directory) {
  const entries = fs.readdirSync(directory, { withFileTypes: true });
  return entries.flatMap((entry) => {
    const target = path.join(directory, entry.name);
    if (entry.isDirectory()) return listEtsFiles(target);
    return entry.name.endsWith('.ets') ? [target] : [];
  });
}

function validateFile(file) {
  const source = fs.readFileSync(file, 'utf8');
  let mode = 'code';
  let line = 1;
  let column = 0;

  for (let index = 0; index < source.length; index += 1) {
    const character = source[index];
    const next = source[index + 1];
    column += 1;
    if (character === '\n') {
      line += 1;
      column = 0;
      if (mode === 'line-comment') mode = 'code';
      if (mode === 'single-quote' || mode === 'double-quote') {
        throw new Error(`${file}:${line - 1}: unterminated string literal`);
      }
      continue;
    }

    if (mode === 'line-comment') continue;
    if (mode === 'block-comment') {
      if (character === '*' && next === '/') {
        mode = 'code';
        index += 1;
        column += 1;
      }
      continue;
    }
    if (mode === 'single-quote' || mode === 'double-quote' || mode === 'template') {
      if (character === '\\') {
        index += 1;
        column += 1;
        continue;
      }
      if ((mode === 'single-quote' && character === "'") ||
          (mode === 'double-quote' && character === '"') ||
          (mode === 'template' && character === '`')) {
        mode = 'code';
      }
      continue;
    }

    if (character === '/' && next === '/') {
      mode = 'line-comment';
      index += 1;
      column += 1;
    } else if (character === '/' && next === '*') {
      mode = 'block-comment';
      index += 1;
      column += 1;
    } else if (character === "'") {
      mode = 'single-quote';
    } else if (character === '"') {
      mode = 'double-quote';
    } else if (character === '`') {
      mode = 'template';
    }
  }

  if (mode === 'single-quote' || mode === 'double-quote' || mode === 'template' || mode === 'block-comment') {
    throw new Error(`${file}:${line}:${column}: unterminated ${mode}`);
  }
}

const root = path.resolve('entry/src/main/ets');
for (const file of listEtsFiles(root)) validateFile(file);
console.log('ArkTS lexical validation passed.');
