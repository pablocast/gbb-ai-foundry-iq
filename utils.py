import json
import re


def _parse_response_parts(resp_obj):
    raw = resp_obj.model_dump() if hasattr(resp_obj, "model_dump") else resp_obj
    if not isinstance(raw, dict):
        raise TypeError("Expected a dict-like response object")

    citation_re = re.compile(r"【(\d+):(\d+)†([^】]+)】")
    doc_block_re = re.compile(
        r"【(?P<m>\d+):(?P<s>\d+)†(?P<src>[^】]+)】\s*(?P<body>\{.*?\})(?=\s*【\d+:\d+†[^】]+】|\s*Visible:|\Z)",
        re.DOTALL,
    )

    assistant_text = ""
    final_message = next(
        (
            item
            for item in raw.get("output", [])
            if item.get("type") == "message"
            and item.get("role") == "assistant"
            and item.get("phase") == "final_answer"
        ),
        None,
    )

    if final_message:
        for part in final_message.get("content", []):
            if part.get("type") == "output_text" and isinstance(part.get("text"), str):
                assistant_text = part["text"]
                break

    if not assistant_text:
        assistant_text = getattr(resp_obj, "output_text", "") or ""

    # Citations actually used in the final assistant text.
    citations_in_answer = []
    seen = set()
    for m, s, src in citation_re.findall(assistant_text):
        key = (int(m), int(s), src)
        if key not in seen:
            seen.add(key)
            citations_in_answer.append(key)

    # Parse MCP tool payload blocks so references can be human-readable.
    docs_by_key = {}
    for item in raw.get("output", []):
        if item.get("type") != "mcp_call":
            continue
        tool_output = item.get("output")
        if not isinstance(tool_output, str):
            continue

        for match in doc_block_re.finditer(tool_output):
            m = int(match.group("m"))
            s = int(match.group("s"))
            src = match.group("src")
            body = match.group("body")

            parsed = None
            try:
                parsed = json.loads(body)
            except json.JSONDecodeError:
                parsed = None

            docs_by_key[(m, s, src)] = parsed

    clean_text = citation_re.sub("", assistant_text).strip()
    clean_text = re.sub(r"[ \t]+\n", "\n", clean_text)
    clean_text = re.sub(r"\n{3,}", "\n\n", clean_text)

    return clean_text, citations_in_answer, docs_by_key


def _reference_label(doc, src_name):
    if not isinstance(doc, dict):
        return f"{src_name} result"

    name = doc.get("ProductName") or doc.get("title") or doc.get("name")
    category = doc.get("ProductCategory")
    product_id = doc.get("ProductID")
    page = doc.get("Page") or doc.get("page")
    blob_url = doc.get("BlobURL") or doc.get("blob_url")

    if name and category and product_id and page:
        return f"{name} - {category} ({product_id}, Page {page})"
    if name and category and product_id:
        return f"{name} - {category} ({product_id})"
    if name and category:
        return f"{name} - {category}"
    if name and page and blob_url:
        return f"{name} (Page {page}) - [Link]({blob_url})"
    if name:
        return str(name)
    return f"{src_name} result"


def extract_references(resp_obj):
    clean_text, citations_in_answer, docs_by_key = _parse_response_parts(resp_obj)

    references = []
    for m, s, src in citations_in_answer:
        doc = docs_by_key.get((m, s, src))
        references.append(
            {
                "message_idx": m,
                "search_idx": s,
                "source_name": src,
                "label": _reference_label(doc, src),
                "document": doc,
            }
        )

    return {
        "response_text": clean_text,
        "references": references,
    }


def format_response_with_references(resp_obj):
    parsed = extract_references(resp_obj)
    clean_text = parsed["response_text"]
    references = parsed["references"]

    lines = [f"Response: {clean_text}", "", "---", "", "**References**:"]

    if references:
        for ref in references:
            lines.append(f"- [{ref['label']}]({ref['message_idx']}:{ref['search_idx']})")
    else:
        lines.append("- No citations found in final answer.")

    return "\n".join(lines)

