# Security Policy

PromptImprover takes security reports seriously. This document defines how to report vulnerabilities and how reports are handled.

## Scope

This policy applies to:

- Source code in this repository
- GitHub workflows and release automation in this repository
- Official release artifacts published from this repository (for example, DMG releases)

## Reporting a Vulnerability (Private)

Use GitHub Security Advisories only:

- Open: [Report a vulnerability](https://github.com/jnjambrin0/PromptImprover/security/advisories/new)

Do not open public Issues or Pull Requests for security vulnerabilities.

## What to Include in a Report

Please include as much of the following as possible:

- Affected version, release tag, or commit SHA
- Impact and severity assessment
- Clear reproduction steps
- Proof of concept (if safe and relevant)
- Environment details (macOS version, tool selection, local setup details)
- Any suggested mitigation or patch direction

## Response Process (Best Effort)

PromptImprover follows a best-effort response model:

- Triage acknowledgment target: within 3 business days
- Validation and severity assessment after acknowledgment
- Periodic status updates during remediation
- Coordinated release/advisory publication once a fix is available

Response times can vary depending on report complexity and maintainer availability.

## Disclosure Policy

- We follow coordinated disclosure.
- Please keep technical details private until a fix or mitigation is published.
- Once resolved, maintainers may publish a security advisory with impact, affected versions, and remediation guidance.

## Out of Scope

Please use regular Issues for:

- General support requests
- Feature requests
- Non-security functional bugs
- Documentation improvements

## Safe Harbor

If you act in good faith and follow this policy, we will not pursue action for security research that:

- Avoids privacy violations, data destruction, and service disruption
- Does not access or modify data beyond what is necessary to demonstrate the issue
- Is reported promptly and privately through GitHub Security Advisories

## Maintainer Configuration Requirement

Maintainers should ensure GitHub private vulnerability reporting is enabled in repository settings so private reports can be submitted.

