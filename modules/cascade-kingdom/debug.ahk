; Cascade Kingdom logging: verbose debug lines and errors, both in the shared log.

DebugLog(message) => SuiteState.Log.Debug("Cascade Kingdom", message)

DebugError(context, failure) => SuiteState.Log.Error("Cascade Kingdom / " context, failure)
