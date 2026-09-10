import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const projectSpec = readFileSync(resolve(process.cwd(), '..', 'project.yml'), 'utf8');
const versionMatch = projectSpec.match(/^\s*MARKETING_VERSION:\s*"?((?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*))"?\s*$/m);

if (!versionMatch) {
  throw new Error('Could not read MARKETING_VERSION from project.yml.');
}

export const currentVersion = versionMatch[1];
