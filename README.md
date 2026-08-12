# Data Platform Advisory

Source for [Data Platform Advisory](https://dataplatformadvisory.com/) — Ivan Lima's site on database modernization for AI systems: indexing, performance, CI/CD, vector databases, AI semantics, and data engineering, with an eye on quantum's future impact on data systems.

Built with [Jekyll](https://jekyllrb.com/) and hosted on GitHub Pages, served from the custom domain dataplatformadvisory.com.

## Local development

```bash
bundle install
bundle exec jekyll serve
```

Site will be available at `http://localhost:4000/`.

## Structure

- `_posts/` — blog posts
- `about.md`, `services.md`, `index.md` — site pages
- `_config.yml` — site configuration
- `llms.txt` — AI/answer-engine discovery file
- `CNAME` — custom domain configuration for GitHub Pages
