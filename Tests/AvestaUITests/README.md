# AvestaUI Snapshot Tests

Code review UI snapshots use `swift-snapshot-testing`.

Run compare mode:

```sh
Scripts/test-snapshots.sh verify
```

Update baselines intentionally:

```sh
Scripts/test-snapshots.sh record
```

The snapshot test defaults to `record: .never`, so normal `swift test` runs fail if a baseline is missing or different instead of silently creating a new image.
