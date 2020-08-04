# GAV Introspector

*--==Speedy GAV resolver for Java artifacts==--*

Goal of this script is to determine the *GAV (GroupId ArtifactId Version)* for every Java artifact in provided directory, as quickly as possible and without involving laggy and network intensive build tools (Maven, Gradle, ...). It is clearly hacky here and there but performance is the only indicator that matters: all shots are allowed.

## How To

```sh
gavspector [flags] <directory full of Java artifacts>
```

Supported flags:

- `--fail-fast`, process immediately exits if an artifact cannot be resolved. Default is to continue processing remaining artifacts. In both cases the process will return with a non zero exit code.
- `--unresolved-ext <extension>`, append provided extension to all unresolved artifacts. If `--fail-fast` flag is also enabled, the custom extension will only be appended to the artifact that caused the exit. By default unresolved artifacts are left unchanged.
- `--purge-cache`, flush existing local cache (artifacts' hash). Local cache will be rebuilt from the ground up.

Resolved artifacts are renamed following standard GAV pattern: `<groupId>.<artifactId>-<version>.jar`

## Links

- Maven Search API: <https://search.maven.org/classic/#api>
