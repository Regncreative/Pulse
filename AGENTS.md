# AGENTS.md

# Pulse

> See what Windows is really doing.

---

# Vision

Pulse is a professional Windows diagnostics platform.

Its purpose is to make Windows internals understandable.

Pulse observes.

Pulse explains.

Pulse visualizes.

Pulse never changes Windows.

---

# Mission

Create the best modern Windows observability platform.

Pulse should become the modern replacement for multiple Windows diagnostic tools.

Including but not limited to:

- Event Viewer
- Process Monitor
- Resource Monitor
- Performance Monitor
- ETW viewers

Pulse combines these into one consistent experience.

---

# Philosophy

Windows already knows everything.

Pulse simply reveals it.

Everything must remain read-only.

Never modify operating system behavior.

Never inject into processes.

Never patch Windows.

Never hook Windows.

Never bypass Windows security.

Observation only.

---

# Core Principles

- Read-only
- Local-first
- Offline capable
- No telemetry
- No analytics
- No tracking
- No advertisements
- Privacy first
- Native Windows experience
- Fast startup
- Low memory usage
- Low CPU usage
- Stable
- Professional

---

# Product Goals

Users should understand what Windows is doing.

Not by reading logs.

But by reading events.

Example:

Bad

Application Error
Event ID 1000

Good

Explorer unexpectedly closed.

Windows restarted Explorer.

---

# Product Scope

Pulse can display

- Event Logs
- ETW
- Process lifecycle
- Thread lifecycle
- Service activity
- Driver activity
- Registry activity
- File activity
- Network activity
- Windows Error Reporting
- Crash information
- Performance counters
- Boot information
- Shutdown information

Future

- Plugin system
- Timeline replay
- Session recording
- Diagnostics export
- Crash timeline

---

# What Pulse is NOT

Pulse is NOT

- Antivirus
- Cleaner
- Optimizer
- Registry cleaner
- Booster
- RAM optimizer
- Driver updater
- Malware remover

Never add these features.

---

# UI Philosophy

Modern Windows.

Inspired by

- Windows 11
- Visual Studio
- Sysinternals
- DevTools
- Figma

No visual clutter.

Everything should feel intentional.

---

# UI Principles

Use whitespace.

Readable typography.

Large spacing.

Minimal icons.

Native scrolling.

Virtualized lists.

Fast search.

Dark mode first.

---

# Timeline

The timeline is the primary interface.

Everything should become an event.

Example

Chrome started

↓

Chrome loaded GPU process

↓

Chrome opened TLS connection

↓

Chrome wrote cache

↓

Chrome exited

---

# Information Hierarchy

Level 1

Human language

Example

Windows restarted Explorer.

---

Level 2

Technical summary

Explorer.exe crashed.

---

Level 3

Raw event

Complete XML

---

Never expose technical information first.

---

# Performance

Startup under 1 second.

Idle RAM

<150 MB

Idle CPU

Near zero.

Smooth scrolling

60 FPS minimum.

---

# Architecture

Frontend

Flutter Desktop

Backend

Native Windows service

Communication

IPC

Never use HTTP for local communication.

---

# Data

Everything stays local.

No cloud.

No login.

No account.

No telemetry.

No user tracking.

---

# Code Quality

Readable.

Modular.

Documented.

Self-explanatory.

No magic numbers.

No duplicated code.

No unnecessary abstractions.

---

# Error Handling

Every error must

Explain

Recover

Log

Never silently fail.

---

# Logging

Every subsystem has logging.

Logs should be structured.

Prefer JSON.

Include timestamps.

Never log sensitive user information.

---

# Security

Use official Windows APIs.

Never bypass Windows security.

Never exploit Windows.

Never inject code.

Never elevate privileges without explicit user action.

Never disable security features.

---

# Documentation

Every major module requires

Architecture

Responsibilities

Dependencies

Public API

Examples

Limitations

Future improvements

---

# Development Rules

Always verify assumptions.

Never invent Windows APIs.

Never guess undocumented behavior.

Prefer Microsoft documentation.

If uncertain

Stop

Explain

Wait.

---

# AI Rules

Before implementing

Understand

Research

Verify

Design

Then code.

Never generate placeholder architecture.

Never produce fake implementations.

---

# Git

Small commits.

Clear commit messages.

One feature per commit.

---

# Naming

Clear names.

Avoid abbreviations.

Avoid generic names.

Prefer

ProcessTimeline

instead of

PTManager

---

# Future Modules

Event Engine

Timeline Engine

ETW Engine

Registry Engine

File Engine

Network Engine

Driver Engine

WER Engine

Plugin Engine

Search Engine

Export Engine

Diagnostics Engine

---

# Long-Term Vision

Pulse should become the most modern Windows observability platform.

A tool that lets users understand Windows through beautiful, readable, real-time diagnostics.

Every feature should answer one question:

"What is Windows doing right now?"

---

# Architecture

Pulse technical architecture is documented in [docs/architecture/README.md](docs/architecture/README.md).

**v1 scope:** Windows Event Log → Collector → IPC → Timeline → human-readable events only. ETW, WMI, and plugins are future milestones.

Read that package (including ADR-007 and ADR-008) before implementing any production code.
