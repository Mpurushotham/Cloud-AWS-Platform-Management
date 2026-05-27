module.exports = {
  extends: ['@commitlint/config-conventional'],
  rules: {
    'type-enum': [
      2,
      'always',
      [
        'feat',     // New feature
        'fix',      // Bug fix
        'docs',     // Documentation only
        'style',    // Formatting, no logic change
        'refactor', // Code refactor without feature/fix
        'perf',     // Performance improvement
        'test',     // Adding or fixing tests
        'chore',    // Build process, dependencies
        'ci',       // CI/CD changes
        'security', // Security hardening or fixes
        'infra',    // Infrastructure changes (Terraform, CDK)
        'revert',   // Revert a commit
      ],
    ],
    'scope-enum': [
      1,
      'always',
      [
        'bootstrap',
        'organizations',
        'networking',
        'security',
        'eks',
        'ecs',
        'rds',
        'cdk',
        'workflows',
        'kyverno',
        'falco',
        'monitoring',
        'idp',
        'docs',
        'deps',
      ],
    ],
    'subject-case': [2, 'always', 'lower-case'],
    'subject-max-length': [2, 'always', 100],
    'body-max-line-length': [1, 'always', 120],
  },
};
