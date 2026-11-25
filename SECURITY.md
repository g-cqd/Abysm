# Security Policy

## Scope

`Abysm` bridges dynamic Objective-C runtime calls. Every selector invocation validates runtime type encodings before dispatch and contains Objective-C exceptions as Swift errors. Never pass untrusted user input as class or selector names.

## Supported Versions

Security fixes land on `main` and the latest tagged release (when releases are published). Pin a specific tag or commit revision for reproducible builds.

## Reporting a Vulnerability

Report security issues privately via [GitHub Security Advisories](https://github.com/g-cqd/Abysm/security/advisories/new). Do not open public issues with exploit details or sensitive material. Include the commit or version, platform, and a minimal reproduction.
