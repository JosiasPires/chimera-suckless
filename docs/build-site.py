#!/usr/bin/env python3
"""Gera o site estatico do projeto a partir dos .md (fonte unica).

Uso: python3 docs/build-site.py [repo-root] [out-dir]
Padrao: repo-root = pai de docs/, out-dir = <repo>/site.
Requer: python3-markdown (apt: python3-markdown).
"""
import pathlib
import re
import sys

try:
    import markdown
except ImportError:
    sys.exit("falta python3-markdown (apt install python3-markdown)")

ROOT = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else pathlib.Path(__file__).resolve().parent.parent
OUT = pathlib.Path(sys.argv[2]) if len(sys.argv) > 2 else (ROOT / "site")

PAGES = [
    ("index.html", "Início", ROOT / "README.md"),
    ("guia.html", "Guia de instalação", ROOT / "GUIDE.md"),
    ("ci.html", "CI e empacotamento", ROOT / "docs" / "CI.md"),
    ("pacotes.html", "Pacotes", None),
]

CSS = """\
:root { color-scheme: dark; }
body { background: #0a0a07; color: #e6e1dc; font-family: monospace;
       max-width: 72em; margin: 0 auto; padding: 1em 1.5em 4em; line-height: 1.55; }
nav { border-bottom: 1px solid #33302a; padding-bottom: .6em; margin-bottom: 1.5em; }
nav a { color: #8ab4ff; margin-right: 1.2em; text-decoration: none; }
nav a:hover { text-decoration: underline; }
nav .repo { float: right; margin-right: 0; }
h1, h2, h3 { color: #f0e68c; }
h2 { border-bottom: 1px solid #33302a; padding-bottom: .2em; }
a { color: #8ab4ff; }
code { background: #1a1915; padding: .1em .3em; border-radius: 3px; }
pre { background: #141310; padding: 1em; overflow-x: auto; border: 1px solid #33302a; }
pre code { background: none; padding: 0; }
table { border-collapse: collapse; margin: 1em 0; }
th, td { border: 1px solid #33302a; padding: .4em .8em; text-align: left; }
th { background: #1a1915; }
blockquote { border-left: 3px solid #6a6a5a; margin-left: 0; padding-left: 1em; color: #b8b39a; }
footer { margin-top: 3em; border-top: 1px solid #33302a; padding-top: .6em;
         color: #6a6a5a; font-size: .9em; }
"""

TEMPLATE = """<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title} — chimera-suckless</title>
<link rel="stylesheet" href="style.css">
</head>
<body>
<nav>
<a href="index.html">Início</a>
<a href="guia.html">Guia de instalação</a>
<a href="ci.html">CI e empacotamento</a>
<a href="pacotes.html">Pacotes</a>
<a class="repo" href="https://github.com/JosiasPires/chimera-suckless">GitHub</a>
</nav>
<main>
{body}
</main>
<footer>chimera-suckless — Chimera Linux minimalista (bswc + tiny + UKI). Docs geradas dos .md do repo.</footer>
</body>
</html>
"""


def render_md(path):
    text = path.read_text(encoding="utf-8")
    return markdown.markdown(text, extensions=["fenced_code", "tables", "toc"])


def package_table():
    rows = []
    userdir = ROOT / "cports" / "user"
    seen = set()
    for tmpl in sorted(userdir.glob("*/template.py")):
        real = tmpl.resolve()
        if real in seen:
            continue
        seen.add(real)
        text = tmpl.read_text(encoding="utf-8")
        name = re.search(r'^pkgname = "([^"]+)"', text, re.M)
        ver = re.search(r'^pkgver = "([^"]+)"', text, re.M)
        rel = re.search(r"^pkgrel = (\d+)", text, re.M)
        desc = re.search(r'^pkgdesc = "([^"]+)"', text, re.M)
        if not (name and ver):
            continue
        version = ver.group(1) + ("-r" + rel.group(1) if rel else "")
        subpkgs = re.findall(r'@subpackage\("([^"]+)"\)', text)
        rows.append((name.group(1), version, desc.group(1) if desc else "", ", ".join(subpkgs)))
    body = ["<h1>Pacotes do overlay</h1>",
            "<p>Buildados do fonte no GitHub Actions e publicados no repo apk "
            "(<code>user/x86_64/</code>). Instalação: ver Guia, seção 6b.</p>",
            "<table><tr><th>pacote</th><th>versão</th><th>descrição</th><th>subpacotes</th></tr>"]
    for name, version, desc, subs in rows:
        body.append(f"<tr><td><code>{name}</code></td><td>{version}</td>"
                    f"<td>{desc}</td><td><code>{subs}</code></td></tr>")
    body.append("</table>")
    body.append("<h2>Usar o repositório</h2>")
    body.append("<pre><code>echo \"https://josiaspires.github.io/chimera-suckless/user\" \\\n"
                "    &gt; /etc/apk/repositories.d/10-overlay.list\n"
                "curl -fsSL https://raw.githubusercontent.com/JosiasPires/chimera-suckless/main/keys/ci.rsa.pub \\\n"
                "    -o /etc/apk/keys/ci.rsa.pub\n"
                "apk update</code></pre>")
    return "\n".join(body)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "style.css").write_text(CSS, encoding="utf-8")
    for fname, title, src in PAGES:
        if src is not None:
            body = render_md(src)
        else:
            body = package_table()
        (OUT / fname).write_text(
            TEMPLATE.format(title=title, body=body), encoding="utf-8"
        )
        print("wrote", fname)


if __name__ == "__main__":
    main()
