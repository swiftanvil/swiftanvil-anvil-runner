# ``AnvilRunner``

Self-hosted GitHub Actions runner lifecycle management for macOS.

## Overview

`AnvilRunner` downloads, configures, starts, stops, and removes GitHub Actions runner instances on macOS with safety policies and cleanup controls.

## Topics

### Lifecycle

- ``RunnerLifecycle``
- ``RunnerConfiguration``

### Provisioning

- ``ProvisioningPlanner``
- ``ProvisioningExecutor``
- ``ProvisioningModels``

### Capabilities

- ``CapabilityDiscovery``
- ``CapabilityModels``

### Health & Cleanup

- ``HealthMonitor``
- ``CleanupPolicy``
- ``CleanupSafetyPolicy``

### Errors

- ``RunnerError``
