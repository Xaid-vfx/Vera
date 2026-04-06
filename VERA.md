# Vera — What & Why

---

## What Is Vera?

Vera is a voice-first daily planning assistant for iOS. In under 5 minutes, you speak your day into existence — no tapping, no typing, no staring at a blank calendar. Vera listens, asks smart follow-up questions, factors in how your body is actually doing today, and hands you back a prioritized schedule that goes straight into your calendar.

You talk. Vera plans.

---

## The Problem

Most people start their day without a real plan. Not because they don't want one — but because making one is friction-heavy and feels like work before the work.

### The status quo is broken in three ways

**1. Planning tools are built for looking, not thinking.**
Apps like Notion, Todoist, and Apple Reminders are great at storing tasks. They are terrible at helping you decide what to actually do today. You open them, stare at a list of 40 things, and close them. The decision-making is still entirely on you.

**2. Your body is invisible to your planner.**
You might have slept 5 hours, have a recovery score of 28%, and still schedule a brutal workout and four back-to-back meetings. No planning app knows that. They treat every day as if you wake up at 100%. You don't.

**3. The calendar and the to-do list don't talk to each other.**
You plan tasks in one app and your calendar lives in another. You manually try to reconcile them — if you do it at all. Most people end up with tasks that collide with meetings they forgot about.

### The result

People either over-plan (ambitious morning list, abandoned by noon) or under-plan (reactive days, low output, end-of-day guilt). Both are the same problem: no grounded, personalized plan built around today's reality.

---

## Why Now?

Three things converged to make Vera possible right now:

1. **On-device speech recognition is good enough.** Apple's SFSpeechRecognizer works offline, in real time, with no latency. Voice input is no longer a gimmick.

2. **LLMs are fast and cheap enough for a planning turn.** Groq runs llama-3.3-70b in ~800ms. A full planning conversation — 5-6 turns — costs fractions of a cent.

3. **Wearables generate real recovery signal.** Whoop, Apple Watch, and Oura now produce HRV, strain, and sleep data that is genuinely predictive of cognitive and physical capacity. That signal was always there. No one has piped it into a planner before.

---

## How Vera Solves It

| Problem | Vera's answer |
|---------|--------------|
| Planning takes too long | Full session in under 5 minutes, voice only |
| No awareness of your physical state | Reads Whoop recovery, HRV, sleep before you say a word |
| Tasks collide with calendar | Reads today's events, flags conflicts in real time |
| Plan never reaches the calendar | Writes the finalized plan to Google Calendar automatically |
| One-size-fits-all recommendations | AI adjusts task intensity suggestions to your recovery level |

### The experience in four steps

1. **Tap mic** — Vera greets you with a 1-2 sentence health briefing: your recovery score, whether your sleep was restorative, yesterday's strain.
2. **Talk through your day** — dump everything on your mind. Vera extracts tasks, asks clarifying questions one at a time, and suggests time blocks based on your calendar gaps.
3. **Confirm** — say "that's everything" and Vera organizes the tasks by priority, flags anything that conflicts with your recovery or calendar.
4. **Done** — the plan is written to Google Calendar. You open your day and it's already structured.

---

## Who Is Vera For?

### Primary: High-performers who track their health

People who wear a Whoop or Apple Watch, care about HRV and recovery, and already think about performance optimization. They are used to data informing their physical training — Vera extends that same logic to their workday.

**Profile:**
- Age 25–40
- Founders, operators, athletes, consultants
- Already use productivity tools but feel like they're fighting them
- Morning routine oriented — they want a clean start to the day

**Why they care:** They've invested in understanding their body. Vera is the first tool that actually uses that data to shape their schedule.

---

### Secondary: Busy professionals who lose mornings to context-switching

People who open their laptop, get pulled into Slack, skip planning entirely, and feel scattered by 10am. They aren't necessarily health-data obsessed — they just want someone (something) to quickly tell them what to focus on.

**Profile:**
- Age 28–45
- Knowledge workers: PMs, engineers, designers, marketers
- High meeting load, fragmented attention
- Use calendar religiously but to-do lists loosely

**Why they care:** Vera gives them a structured start without the overhead of a planning system to maintain.

---

### Tertiary: ADHD users and people who struggle with task initiation

Starting is the hardest part for a large subset of people. A blank list is paralyzing. A voice conversation that walks you through your day removes the activation energy from planning. You don't decide what to plan — you just answer questions.

**Profile:**
- ADHD diagnoses or subclinical executive function challenges
- Often have good intentions with planning apps, fail at consistency
- Respond better to conversational prompts than blank canvases

**Why they care:** Vera meets them in conversation rather than demanding they organize themselves first.

---

## Why Voice Specifically?

Voice is not a UX gimmick here. It is the core thesis.

**Planning is thinking out loud.** Most people, when asked what they need to do today, will talk through it naturally if given a patient listener. They wouldn't type it — but they'll say it. Voice unlocks honest, unfiltered brain dumps that a keyboard never does.

**Friction is the enemy of planning.** Every additional tap, field, or decision point is an exit ramp. A conversation has almost zero friction — you're just talking.

**Conversation forces completeness.** A to-do app lets you add "gym" and move on. Vera asks: when? how long? given your recovery is 28%, are you sure you want to push hard today? The conversational format naturally surfaces the detail that makes a plan actionable.

---

## The Bigger Vision

Vera is the beginning of a planner that knows you — not just your tasks, but your energy, your patterns, your limits.

Near term:
- Apple Watch integration (resting heart rate, readiness trends)
- Weekly pattern learning ("you're usually low energy on Thursdays")
- Proactive check-ins mid-day ("you have 90 minutes before your 3pm — want to tackle the deep work block?")

Longer term:
- Vera becomes your operating system for the day, not just the morning
- Integrates with work tools (Linear, Notion, Slack) to pull actual task context
- Learns which tasks you consistently deprioritize and surfaces them at the right moment

The end state: a planning layer that works with how you actually function, not how a productivity framework assumes you should.

---

## Why We're Building This

Most productivity software is built for an idealized version of the user — rested, focused, infinitely disciplined. Real people are none of those things consistently.

We think the right intervention is not another system to maintain — it's a 5-minute conversation every morning with something that actually knows how you're doing. Vera is that.

The goal is simple: more people end their day feeling like they got the right things done.
