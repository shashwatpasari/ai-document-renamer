# Document Renamer

An AI-powered tool that automatically reads your documents (PDFs, images) and renames them with meaningful names based on their content. It uses a local vision model via [Ollama](https://ollama.com) — no data ever leaves your machine.

## How It Works

1. Scans your input folder for PDFs, JPGs, and PNGs
2. Sends each document to a local AI vision model (Gemma 3 4B)
3. Extracts the **person's name**, **organisation**, **document type**, and **date**
4. Copies the file into a monthly subfolder with a clean, descriptive name

### Example

```
Before:  Statements20250831.pdf
After:   Renamed Documents/August 2025/John Smith - Commonwealth Bank Of Australia - bank statement.pdf

Before:  18 Feb.pdf
After:   Renamed Documents/February 2026/Jane Doe - ANZ - bank statement.pdf
```

## Quick Start

### macOS

**1. Install**

```bash
bash install_mac.sh
```

**2. Run**

```bash
bash run_now_mac.sh
```

**3. Dry Run** (preview without copying)

```bash
bash run_now_mac.sh --dry-run
```

---

### Windows

> Open PowerShell as **Administrator** for the first install.

**1. Install**

```powershell
.\install_windows.ps1
```

> If you get an execution policy error, run this first:
> ```powershell
> Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
> ```

**2. Run**

```powershell
.\run_now_windows.ps1
```

**3. Dry Run** (preview without copying)

```powershell
.\run_now_windows.ps1 --dry-run
```

---

The install script will:
- Install Python and Ollama if not already installed (via Homebrew on macOS, winget on Windows)
- Pull the `gemma3:4b` vision model (~3.3 GB download)
- Create a Python virtual environment with dependencies
- Ask you for the folder containing your documents
- Generate a `config.py` with your settings

Processed files are **copied** (not moved) into the output folder, organised by month.

## Configuration

After running the install script, a `config.py` is created with your settings:

| Setting | Description |
|---|---|
| `INPUT_FOLDER` | Folder to scan for documents |
| `OUTPUT_FOLDER` | Where renamed copies are saved |
| `MODEL` | Ollama vision model to use (default: `gemma3:4b`) |
| `SUPPORTED_EXTENSIONS` | File types to process (`.pdf`, `.jpg`, `.jpeg`, `.png`) |
| `DRY_RUN` | Set to `True` to preview without copying |

You can edit `config.py` directly to change any of these.

## Project Structure

```
Document renamer/
├── install_mac.sh          # macOS setup script
├── install_windows.ps1     # Windows setup script
├── run_now_mac.sh          # macOS run script
├── run_now_windows.ps1     # Windows run script
├── run.py                  # Entry point, parses CLI args
├── processor.py            # Core logic: OCR, AI extraction, file renaming
├── config.py               # Generated settings (input/output folders, model)
└── venv/                   # Python virtual environment (auto-created)
```

## Supported File Types

- `.pdf` — Converted to images page-by-page, then analysed
- `.jpg` / `.jpeg` / `.png` — Analysed directly

## Troubleshooting

| Problem | Solution |
|---|---|
| `ollama: command not found` | Run the install script again |
| `client version is ...` warning | The run scripts handle this automatically — they restart the Ollama server |
| Model crashes or errors | Try `ollama rm gemma3:4b && ollama pull gemma3:4b` |
| Wrong folder path | Edit `INPUT_FOLDER` in `config.py` |
| Files not being found | Check that file extensions are in `SUPPORTED_EXTENSIONS` |
| PowerShell execution policy error | Run `Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned` |
