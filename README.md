Oracle database with custom schema for integration testing.

## How to Use in Other Projects

Create `.github/workflows/integration-tests.yml` in your project:

```yaml
name: Integration Tests

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  integration-test:
    uses: owner/emr-dynamic-database/.github/workflows/oracle-test-db.yml@main
    with:
      java-version: "17"
      test-command: "mvn verify -Pintegration-test"
      working-directory: "."
      # Optional: add custom migrations specific to your project
      # custom-migrations-path: "src/test/resources/migrations"
```

## Workflow Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `java-version` | No | `"17"` | Java version for tests |
| `test-command` | **Yes** | - | Command to run (e.g., `mvn verify`, `./gradlew integrationTest`) |
| `working-directory` | No | `"."` | Directory for test command |
| `custom-migrations-path` | No | `""` | Path to project-specific SQL migrations |

## Environment Variables Available to Your Tests

```properties
DB_HOST=localhost
DB_PORT=1521
DB_SERVICE=XEPDB1
DB_USER=my_user
DB_PASSWORD=abacate123
SPRING_DATASOURCE_URL=jdbc:oracle:thin:@localhost:1521/XEPDB1
SPRING_DATASOURCE_USERNAME=my_user
SPRING_DATASOURCE_PASSWORD=abacate123
```

## Test Configuration Examples

### Java (RestAssured / JUnit)

```java
@BeforeAll
static void setup() {
    String dbUrl = System.getenv("SPRING_DATASOURCE_URL");
    String dbUser = System.getenv("DB_USER");
    String dbPassword = System.getenv("DB_PASSWORD");
    // Configure your DataSource or connection pool
}
```

### Spring Boot (`application-test.properties`)

```properties
spring.datasource.url=${SPRING_DATASOURCE_URL}
spring.datasource.username=${DB_USER}
spring.datasource.password=${DB_PASSWORD}
```

## Run Locally with Docker Compose

```bash
docker-compose down -v 
docker-compose up -d 
docker logs -f database_migration_runner
```
