# core/contracts/

Shared contracts for cross-module communication.

## Scope

- Event contracts used by capture, storage, and orchestrator.
- Knowledge contracts used by knowledge and skills pipeline.
- Error/status code catalog shared by runtime modules.

## Current Contracts

- `CaptureEventContracts.swift`: `RawEvent`, `ContextSnapshot`, `NormalizedEvent`.

## Rule

Any payload crossing module boundaries must reference a contract defined in this directory.
