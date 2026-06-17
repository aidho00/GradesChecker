# Flexible WAMP/XAMPP Deployment

The project does not depend on WAMP-specific or XAMPP-specific code.

Only the folder location and URL differ:

| Stack | PHP folder | Default URL |
|---|---|---|
| WAMP | `C:\wamp64\www\grades_checker_api` | `http://localhost/grades_checker_api/...` |
| XAMPP | `C:\xampp\htdocs\grades_checker_api` | `http://localhost/grades_checker_api/...` |

If Apache uses port 8080:

```text
http://localhost:8080/grades_checker_api/check_grades.php
```

If MySQL uses a non-default port, edit `DB_PORT` in `config.php`.
