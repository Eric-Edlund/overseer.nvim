#!/usr/bin/env python
import json
import os
import os.path
import re
import subprocess
import textwrap
from collections import defaultdict
from typing import Any, Dict, List, Optional, Tuple

HERE = os.path.dirname(__file__)
ROOT = os.path.abspath(os.path.join(HERE, os.path.pardir))
README = os.path.join(ROOT, "README.md")
DOC = os.path.join(ROOT, "doc", "overseer.txt")


def indent(lines: List[str], amount: int) -> List[str]:
    ret = []
    for line in lines:
        if amount >= 0:
            ret.append(" " * amount + line)
        else:
            space = re.match(r"[ \t]+", line)
            if space:
                ret.append(line[min(abs(amount), space.span()[1]) :])
            else:
                ret.append(line)
    return ret


def replace_section(file: str, start_pat: str, end_pat: str, lines: List[str]) -> None:
    prefix_lines: List[str] = []
    postfix_lines: List[str] = []
    file_lines = prefix_lines
    found_section = False
    with open(file, "r", encoding="utf-8") as ifile:
        inside_section = False
        for line in ifile:
            if inside_section:
                if re.match(end_pat, line):
                    inside_section = False
                    file_lines = postfix_lines
                    file_lines.append(line)
            else:
                if re.match(start_pat, line):
                    inside_section = True
                    found_section = True
                file_lines.append(line)

    if inside_section or not found_section:
        raise Exception(f"could not find file section {start_pat}")

    all_lines = prefix_lines + lines + postfix_lines
    with open(file, "w", encoding="utf-8") as ofile:
        ofile.write("".join(all_lines))


def read_section(
    filename: str,
    start_pat: str,
    end_pat: str,
    inclusive: Tuple[bool, bool] = (False, False),
) -> List[str]:
    lines = []
    with open(filename, "r", encoding="utf-8") as ifile:
        inside_section = False
        for line in ifile:
            if inside_section:
                if re.match(end_pat, line):
                    if inclusive[1]:
                        lines.append(line)
                    break
                lines.append(line)
            elif re.match(start_pat, line):
                inside_section = True
                if inclusive[0]:
                    lines.append(line)
    return lines


def read_nvim_json(lua: str) -> Any:
    cmd = f"nvim --headless --noplugin -u /dev/null -c 'set runtimepath+=.' -c 'lua print(vim.json.encode({lua}))' +qall"
    print(cmd)
    code, txt = subprocess.getstatusoutput(cmd)
    if code != 0:
        raise Exception(f"Error exporting data from overseer: {txt}")
    try:
        return json.loads(txt)
    except json.JSONDecodeError as e:
        raise Exception(f"Json decode error: {txt}") from e


def update_config_options():
    config_file = os.path.join(ROOT, "lua", "overseer", "config.lua")
    opt_lines = read_section(config_file, r"^local default_config =", r"^}$")
    replace_section(
        README,
        r"^require\(\"overseer\"\).setup\({$",
        r"^}\)$",
        opt_lines,
    )


def format_param(name: str, param: Dict) -> str:
    typestr = param["type"]
    if "subtype" in param:
        typestr += "[" + str(param["subtype"]["type"]) + "]"
    pieces = [f"**{name}**[{typestr}]:"]
    required = not param.get("optional")
    if param.get("desc"):
        pieces.append(param["desc"])
    if param.get("default") is not None:
        pieces.append("(default `%s`)" % json.dumps(param["default"]))
        required = False
    line = " ".join(pieces)
    if required:
        line = "\\*" + line
    return line


def format_md_table_row(
    data: Dict, column_names: List[str], max_widths: Dict[str, int]
) -> str:
    cols = []
    for col in column_names:
        cols.append(data[col].ljust(max_widths[col]))
    return "| " + " | ".join(cols) + " |\n"


def format_md_table(rows: List[Dict], column_names: List[str]) -> List[str]:
    max_widths: Dict[str, int] = defaultdict(lambda: 1)
    for row in rows:
        for col in column_names:
            max_widths[col] = max(max_widths[col], len(row[col]))
    lines = []
    titles = []
    for col in column_names:
        titles.append(col.ljust(max_widths[col]))
    lines.append("| " + " | ".join(titles) + " |\n")
    seps = []
    for col in column_names:
        seps.append(max_widths[col] * "-")
    lines.append("| " + " | ".join(seps) + " |\n")
    for row in rows:
        lines.append(format_md_table_row(row, column_names, max_widths))
    return lines


def update_components_md():
    components = read_nvim_json('require("overseer.component").get_all_descriptions()')
    doc = os.path.join(ROOT, "doc", "components.md")
    lines = ["# Built-in components\n", "\n"]
    for comp in components:
        title = f"## [{comp['name']}](../lua/overseer/component/{comp['name']}.lua)\n\n"
        lines.append(title)
        content_lines = []
        if comp.get("desc"):
            content_lines.append(comp["desc"])
        if comp.get("params"):
            for k, v in sorted(comp["params"].items()):
                content_lines.append(format_param(k, v))
        for i, line in enumerate(content_lines):
            if i < len(content_lines) - 1:
                content_lines[i] = line + " \\\n"
            else:
                content_lines[i] = line + "\n"
        lines.extend(content_lines)
        lines.append("\n")
    with open(doc, "w", encoding="utf-8") as ofile:
        ofile.writelines(lines)


def update_commands_md():
    commands = read_nvim_json('require("overseer").get_all_commands()')
    lines = ["\n"]
    rows = []
    for command in commands:
        cmd = command["cmd"]
        if command["def"].get("bang"):
            cmd += "[!]"
        rows.append(
            {
                "Command": "`" + cmd + "`",
                "arg": command.get("args", ""),
                "description": command["def"]["desc"],
            }
        )
    lines.extend(format_md_table(rows, ["Command", "arg", "description"]))
    lines.append("\n")
    replace_section(
        README,
        r"^## Commands",
        r"^#",
        lines,
    )


def count_special(base: str, char: str) -> int:
    c = base.count(char)
    return 2 * (c // 2)


def vimlen(string: str) -> int:
    return len(string) - sum([count_special(string, c) for c in "`|*"])


def leftright(left: str, right: str, width: int = 80) -> str:
    spaces = max(1, width - vimlen(left) - vimlen(right))
    return left + spaces * " " + right + "\n"


def wrap(text: str, indent: int = 0, width: int = 80) -> List[str]:
    return [
        line + "\n"
        for line in textwrap.wrap(
            text,
            initial_indent=indent * " ",
            subsequent_indent=indent * " ",
            width=width,
        )
    ]


def get_commands_vimdoc() -> "VimdocSection":
    section = VimdocSection("Commands", "overseer-commands", ["\n"])
    commands = read_nvim_json('require("overseer").get_all_commands()')
    for command in commands:
        cmd = command["cmd"]
        if command["def"].get("bang"):
            cmd += "[!]"
        if "args" in command:
            cmd += " " + command["args"]
        section.body.append(leftright(cmd, f"*:{command['cmd']}*"))
        section.body.extend(wrap(command["def"]["desc"], 4))
        section.body.append("\n")
    return section


def get_options_vimdoc() -> "VimdocSection":
    section = VimdocSection("options", "overseer-options")
    config_file = os.path.join(ROOT, "lua", "overseer", "config.lua")
    opt_lines = read_section(config_file, r"^local default_config =", r"^}$")
    lines = ["\n", ">\n", '    require("overseer").setup({\n']
    lines.extend(indent(opt_lines, 4))
    lines.extend(["    })\n", "<\n"])
    section.body = lines
    return section


def trim_newlines(lines: List[str]) -> List[str]:
    while lines and lines[0] == "\n":
        lines.pop(0)
    while lines and lines[-1] == "\n":
        lines.pop()
    return lines


class VimdocSection:
    def __init__(
        self,
        name: str,
        tag: str,
        body: Optional[List[str]] = None,
        sep: str = "-",
        width: int = 80,
    ):
        self.name = name
        self.tag = tag
        self.body = body or []
        self.sep = sep
        self.width = width

    def get_body(self) -> List[str]:
        return self.body

    def render(self) -> List[str]:
        lines = [
            self.width * self.sep + "\n",
            leftright(self.name.upper(), f"*{self.tag}*", self.width),
            "\n",
        ]
        lines.extend(trim_newlines(self.get_body()))
        lines.append("\n")
        return lines


class VimdocToc(VimdocSection):
    def __init__(self, name: str, tag: str, width: int = 80):
        super().__init__(name, tag, width=width)
        self.entries: List[Tuple[str, str]] = []
        self.padding = 2

    def get_body(self) -> List[str]:
        lines = []
        for i, (name, tag) in enumerate(self.entries):
            left = self.padding * " " + f"{i+1}. {name.capitalize()}"
            tag_start = self.width - 2 * self.padding - vimlen(tag)
            lines.append(left.ljust(tag_start, ".") + f"|{tag}|\n")
        return lines


class Vimdoc:
    def __init__(self, filename: str, tags: List[str], width: int = 80):
        self.prefix = [f"*{filename}*\n", " ".join(f"*{tag}*" for tag in tags) + "\n"]
        self.sections: List[VimdocSection] = []
        self.width = width

    def render(self) -> List[str]:
        header = self.prefix[:]
        body = []
        toc = VimdocToc("CONTENTS", "overseer-contents", width=self.width)
        for section in self.sections:
            toc.entries.append((section.name, section.tag))
            body.extend(section.render())
        body.append(self.width * "=" + "\n")
        body.append("vim:tw=80:ts=2:ft=help:norl:syntax=help:\n")
        return header + toc.render() + body


def convert_md_link(match):
    text = match[1]
    dest = match[2]
    if dest.startswith("#"):
        return f"|{dest[1:]}|"
    else:
        return text


MD_LINK_PAT = re.compile(r"\[([^\]]+)\]\(([^\)]+)\)")
MD_BOLD_PAT = re.compile(r"\*\*([^\*]+)\*\*")
MD_LINE_BREAK_PAT = re.compile(r"\s*\\$")


def convert_markdown_to_vimdoc(lines: List[str]) -> List[str]:
    while lines[0] == "\n":
        lines.pop(0)
    while lines[-1] == "\n":
        lines.pop()
    i = 0
    code_block = False
    while i < len(lines):
        line = lines[i]
        if line.startswith("```"):
            code_block = not code_block
            if code_block:
                lines[i] = ">\n"
            else:
                lines[i] = "<\n"
        else:
            if code_block:
                lines[i] = 4 * " " + line
            else:
                line = MD_LINK_PAT.sub(convert_md_link, line)
                line = MD_BOLD_PAT.sub(lambda x: x[1], line)
                line = MD_LINE_BREAK_PAT.sub("", line)

                if len(line) > 80:
                    new_lines = wrap(line)
                    lines[i : i + 1] = new_lines
                    i += len(new_lines)
                    continue
                else:
                    lines[i] = line
        i += 1
    return lines


def convert_md_section(
    start_pat: str,
    end_pat: str,
    section_name: str,
    section_tag: str,
    inclusive: Tuple[bool, bool] = (False, False),
) -> VimdocSection:
    lines = read_section(README, start_pat, end_pat, inclusive)
    lines = convert_markdown_to_vimdoc(lines)
    return VimdocSection(section_name, section_tag, lines)


def generate_vimdoc():
    doc = Vimdoc("overseer.txt", ["Overseer", "overseer", "overseer.nvim"])
    doc.sections.extend(
        [
            get_commands_vimdoc(),
            get_options_vimdoc(),
            convert_md_section(
                "^## Running tasks", "^#", "Running tasks", "overseer.run_tasks"
            ),
            convert_md_section("^### Custom tasks", "^#", "Tasks", "overseer.tasks"),
            convert_md_section(
                "^#### Template definition", "^#", "Templates", "overseer.templates"
            ),
            convert_md_section(
                "^#### Template providers",
                "^#",
                "Template providers",
                "overseer.template-providers",
            ),
            convert_md_section("^### Actions", "^#", "Actions", "overseer.actions"),
            convert_md_section(
                "^### Custom components", "^#", "Components", "overseer.components"
            ),
            convert_md_section(
                "^#### Task result", "^#", "Task result", "overseer.task-result"
            ),
            convert_md_section(
                "^### Parameters", "^#", "Parameters", "overseer.params"
            ),
            # TODO highlights
        ]
    )

    # TODO check for missing tags
    with open(DOC, "w", encoding="utf-8") as ofile:
        ofile.writelines(doc.render())


def main() -> None:
    """Update the README"""
    update_config_options()
    update_components_md()
    update_commands_md()
    generate_vimdoc()


if __name__ == "__main__":
    main()
