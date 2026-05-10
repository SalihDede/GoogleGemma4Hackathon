# Working Rules

## Gemini CLI Delegation (Token Optimization)

Gemini CLI is available at system PATH. Use it to offload read-only tasks and reduce Codex token consumption.

### Delegate to Gemini (via Bash):
- File reading and content analysis
- Codebase exploration and project structure discovery
- Code searching (grep/find equivalent)
- Understanding existing code before making changes
- Summarizing large files or directories

### Command pattern on this Windows workspace:
```powershell
echo "PROMPT_HERE" | & "$env:APPDATA\npm\gemini.cmd" 2>&1
```

If `$env:APPDATA` is unavailable, use the explicit shim path:
```powershell
echo "PROMPT_HERE" | & "C:\Users\Hp\AppData\Roaming\npm\gemini.cmd" 2>&1
```

### Keep in Codex (do NOT delegate):
- Code writing, editing, and generation
- Final decision-making and architecture
- Git operations and commits
- Direct user communication
- File creation and modification

### Important:
- Always pipe a clear, specific prompt to Gemini
- Use Gemini's response to inform Codex's actions
- If Gemini fails or gives unclear results, fall back to Codex's own tools
