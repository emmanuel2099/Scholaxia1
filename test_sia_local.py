"""
Sia Local Intelligence Test
────────────────────────────
Tests the enhanced Sia AI directly — no server, no auth, no DB needed.
Just needs: venv activated + GEMINI_API_KEY in .env

Run:
    cd scholaxia
    venv\\Scripts\\activate
    python test_sia_local.py          # full suite
    python test_sia_local.py --quick    # 2 fast tests
"""

import asyncio
import sys
import os

# Fix Windows console encoding for math symbols (→, ², etc.)
if sys.platform == "win32":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

sys.path.insert(0, os.path.dirname(__file__))

env_path = os.path.join(os.path.dirname(__file__), ".env")
if os.path.exists(env_path):
    with open(env_path) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, _, val = line.partition("=")
                os.environ[key.strip()] = val.strip()

from app.core.config import settings
from app.ai.model_backend import run_inference
from app.ai.sia_intelligence import analyze_question, build_intelligence_context
from app.ai.prompt_builder import (
    build_sia_system_prompt, build_chat_user_prompt,
    build_explain_prompt, build_solve_prompt,
)


def divider(title):
    print(f"\n{'=' * 65}")
    print(f"  {title}")
    print(f"{'=' * 65}")


def show(label, text):
    print(f"\n{label}:\n{'-' * 50}")
    print(text.strip())
    print()


async def ask_sia(question, subject, level, name, history=None, label="Sia"):
    analysis = analyze_question(question, subject, level, history)
    intel = build_intelligence_context(analysis)
    system = build_sia_system_prompt(
        student_name=name, subject=subject, education_level=level,
        language="english", raw_input=question, intelligence_context=intel,
    )
    prompt = build_chat_user_prompt(question, name, history)
    print(f"  [intel] type={analysis['question_type']}  temp={analysis['temperature']}  complexity={analysis['complexity']}")
    try:
        result = await run_inference(
            prompt,
            conversation_history=history,
            system_prompt=system,
            max_tokens=4096,
            temperature=analysis["temperature"],
        )
        show(label, result)
        return result
    except Exception as e:
        print(f"  ERROR: {e}")
        return ""


async def main(quick: bool = False):
    print("=" * 65)
    print("  SIA LOCAL INTELLIGENCE TEST (Enhanced Engine)")
    print(f"  Backend: {settings.AI_BACKEND}  |  Model: {settings.GEMINI_MODEL}")
    print("=" * 65)

    if not settings.GEMINI_API_KEY and settings.AI_BACKEND == "gemini":
        print("\n  ERROR: GEMINI_API_KEY missing in .env")
        sys.exit(1)

    divider("TEST 1: Maths solve — step-by-step (SS3)")
    await ask_sia(
        "Solve: x² + 5x + 6 = 0",
        "Mathematics", "SS3", "Emeka",
        label="Sia (should show every step + practice problem)",
    )

    divider("TEST 2: Dual definition — Nigerian + Cambridge (SS2)")
    await ask_sia(
        "What is a noun?",
        "English", "SS2", "Chidi",
        label="Sia (Nigerian + Cambridge definitions)",
    )

    if quick:
        print("=" * 65)
        print("  QUICK TESTS COMPLETE")
        print("=" * 65)
        return

    divider("TEST 3: Biology explain (JSS1)")
    analysis = analyze_question("What is photosynthesis?", "Biology", "JSS1")
    system = build_sia_system_prompt("Amaka", "Biology", "JSS1", "english",
                                     intelligence_context=build_intelligence_context(analysis))
    prompt = build_explain_prompt("photosynthesis", "Biology", "JSS1", "english", "Amaka")
    print(f"  [intel] type={analysis['question_type']}  temp={analysis['temperature']}")
    try:
        show("Sia", await run_inference(prompt, system_prompt=system, temperature=analysis["temperature"]))
    except Exception as e:
        print(f"  ERROR: {e}")

    divider("TEST 4: Conversation follow-up — should NOT restart")
    history = [
        {"role": "user", "content": "What is a verb?"},
        {"role": "assistant", "content": "A verb is a word that describes an action. Examples: run, eat, think."},
    ]
    await ask_sia(
        "Can you give me more examples?",
        "English", "SS1", "Ngozi",
        history=history,
        label="Sia (should continue the lesson)",
    )

    divider("TEST 5: JAMB chemistry depth")
    await ask_sia(
        "What is electrochemistry?",
        "Chemistry", "JAMB", "Bello",
        label="Sia (exam-level depth)",
    )

    print("=" * 65)
    print("  ALL TESTS COMPLETE")
    print("=" * 65)


if __name__ == "__main__":
    quick = "--quick" in sys.argv
    asyncio.run(main(quick=quick))
