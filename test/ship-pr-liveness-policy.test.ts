import { describe, expect, test } from 'bun:test';
import * as fs from 'fs';
import * as path from 'path';

const template = fs.readFileSync(
  path.join(import.meta.dir, '..', '.github', 'PULL_REQUEST_TEMPLATE.md'),
  'utf8',
);

describe('zstack PR liveness policy', () => {
  test('remembers the authenticated repository-owner exemption', () => {
    expect(template).toContain('Repository owner @zeidmahmoud is explicitly exempt');
    expect(template).toContain('gh api user --jq .login');
    expect(template).toMatch(/Git author metadata\s+alone is not sufficient/);
    expect(template).toContain('PR author is @zeidmahmoud (owner exemption)');
  });

  test('retains live ZSTACK PR proof for every other contributor', () => {
    expect(template).toContain('required for external contributors');
    expect(template).toContain('All other contributors');
    expect(template).toContain('`ZSTACK PR` typed LIVE');
    expect(template).toContain('not drawn,\noverlaid, or edited onto the image');
  });
});
