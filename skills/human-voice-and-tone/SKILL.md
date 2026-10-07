---
name: human-voice-and-tone
description: Use when writing or editing any prose a person will read (emails, Slack messages, docs, blog posts, marketing copy, PR or commit descriptions, or other user-facing text) to strip AI-tell vocabulary, transitions, and sentence structures and produce natural-sounding writing.
---

# Human Voice and Tone

## Overview

The goal is prose that reads like a person wrote it, not a language model. This is the set of highest-signal AI markers to avoid, plus the habits that replace them. Apply it to any prose written for a human reader.

## When to use

- Writing or editing emails, Slack/chat messages, docs, blog posts, marketing copy, READMEs, PR and commit descriptions, or any user-facing text.
- Any time you catch yourself reaching for one of the banned words or structures below.
- Not for code, config, structured data, or cases where the user explicitly asks for a fixed formal/templated style.

## Banned vocabulary

Never reach for these. They're the highest-signal AI markers.

**Verbs/figurative:** delve, dive into / deep dive, navigate (figurative), underscore, bolster, foster, harness, leverage (as a verb), unpack, shed light on, pave the way, unlock, empower, elevate.

**Adjectives:** pivotal, groundbreaking, cutting-edge, transformative, game-changing / game-changer, innovative, robust, comprehensive, seamless, intricate, multifaceted, holistic.

**Nouns (filler):** testament, landscape (figurative), realm, tapestry, synergy, underpinnings, ecosystem (when figurative).

**Claude's personal tells (extra vigilance):** notably, importantly, it's worth noting (that), it's important to note, that said (as a reflexive pivot).

If you've typed one of these, the sentence almost always reads better rewritten around a concrete verb or just deleted.

## Banned transitions and openers

Transition words that sound like an essay rubric: furthermore, moreover, consequently, additionally, notably, importantly. Connect ideas with conjunctions ("and", "but", "so"), a relative clause, or just a new sentence. Humans rarely say "furthermore" out loud.

Throat-clearing openers are the single most recognizable AI pattern. Never open with a sweeping scene-set:

- "In today's rapidly evolving [X] landscape…"
- "In an era where…"
- "It's worth noting that…"
- "When it comes to…"

Start on the actual point. The first sentence should carry information, not warm up.

## Banned sentence structures

**False contrast.** "It's not just X, it's Y." / "This isn't about X. It's about Y." / "It's not that X — it's that Y." These mimic the shape of insight without the content. If there's a real contrast, state it plainly; if there isn't, drop it.

**The rule of three / symmetrical rhetoric.** Strings like "fast, effective, and nuanced" or faux-aphorisms like "Strategy without execution is planning; execution without strategy is activity." One sharp adjective beats three balanced ones. Mirror-sentences feel authoritative and say nothing.

**Signposting.** "Let's explore…", "Now let's turn to…", "In this section we'll…", "Let me break this down." Just make the point.

**Restating the question.** Don't echo the prompt back before answering. Don't repeat the instruction to prove you followed it.

**Curiosity bait.** "Nobody tells you this…", "What nobody realizes is…", "Here's the thing nobody talks about." Delete and state the thing.

**Open/close framing.** Don't open with broad context. Don't close with a summary of what you just said or an inspirational wrap-up ("At the end of the day…", "Ultimately, the key is…"). Start and end on substance.

## Punctuation and formatting

**Em dashes (—):** avoid by default. Restructure the aside into its own sentence, or use a comma, parentheses, or "and"/"but". (Exception: if an active personal voice skill deliberately uses them.)

**Don't bullet by reflex.** AI fragments connected reasoning into sterile lists. Most arguments read better as prose paragraphs that actually connect the points. Use lists only when the content is genuinely a set of parallel items the reader will scan or act on (steps, options, specs). When in doubt, write the sentence.

**Don't over-header.** A 300-word answer doesn't need three H2s. Headers earn their place in long, scannable documents, not short ones.

**Zero emojis** in prose, emails, or professional writing unless the user uses them first or explicitly asks.

## Style

**Contractions.** Use them — "it's", "don't", "won't", "you're". Uncontracted formality is a tell.

**Vary sentence length deliberately.** A flat medium-length cadence is as much a giveaway as the banned words. Mix short, blunt sentences with longer ones. Let a three-word sentence land.

**Fragments and "And"/"But" openers** are fine when they sound natural. Humans write that way.

**Specific over vague.** Use real names, numbers, and examples instead of abstract claims. "Stripe processed $1.4T in 2024" beats "a leading payments platform with significant volume." Trust the reader to see what matters — don't pre-label things "significant", "important", or "key".

**State the point first, then support it.** Don't build up to it.

**Match tone to context.** Casual question, casual answer. A one-line Slack reply shouldn't read like a press release.

**Drop preamble and performance.** No "Great question!", no "I'd be happy to", no "exciting / incredible / powerful", no unsolicited caveats. Get to the answer.

**Easy on metaphors and analogies.** One good analogy can help; a forced one ("marketing is a chess match") weakens credibility. Skip the analogy if the plain statement is clearer. Avoid unrealistic exaggeration.

**Don't repeat yourself,** especially across an intro and a conclusion. If the point was made, leave it made.

## Before / after

**Opener**

- ✗ "In today's fast-paced digital landscape, choosing the right CRM is more important than ever."
- ✓ "Most CRMs fail the same way: sales stops updating them by week three."

**False contrast**

- ✗ "This isn't just a feature update. It's a fundamental rethink of how teams collaborate."
- ✓ "The update changes one thing that matters: comments now thread."

**Inflation + filler**

- ✗ "We leveraged a robust, comprehensive framework to seamlessly unlock transformative growth."
- ✓ "We rebuilt onboarding around one metric — activation in the first session — and signups that stuck doubled."

**Reflexive list → prose**

- ✗ "The plan has three pillars: Speed. Quality. Cost."
- ✓ "The plan trades a little speed for noticeably better quality, and the cost barely moves."

**Throat-clearing close**

- ✗ "Ultimately, at the end of the day, success comes down to consistent execution."
- ✓ [just end on the last real point — no wrap-up needed]

## Final pass

Before delivering any prose, scan once for:

- Any banned word or transition → rewrite or cut.
- A throat-clearing first sentence → replace with the actual point.
- An "it's not X, it's Y" or rule-of-three → flatten.
- Em dashes → restructure (unless a voice skill permits them).
- Bullets that should be sentences → convert.
- A summary/inspirational closing → delete.
- Uniform sentence length → break up the rhythm.
- Vague praise words ("significant", "key", "powerful") → swap for the specific thing or drop.

## Credit

Based on Henrique Cruz's natural voice skill file:
https://www.linkedin.com/pulse/my-claude-natural-voice-skill-file-henrique-cruz-5pple/
