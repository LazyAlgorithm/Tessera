---
title: A menu with a UI document
summary: Lay out a settings menu in HTML-like markup, style it, and connect its buttons, text box and bar to a script.
difficulty: Beginner
minutes: 20
order: 5
---
A UI document is a `.tui` file of HTML-like markup with a CSS-like stylesheet. A **UI Document** component draws it over the game and connects it to a script on the same object. This tutorial builds a small settings menu you open and close with Tab.

![The UI editor with a document open](assets/screenshots/ui.jpg)

## 1. Create the document

1. In the **Project** panel, open the `UI` folder, click **+** and choose **UI Document**. Name it `settings_menu`.
2. Double-click it. The **UI** tab opens with an element tree, a live preview and a properties panel.
3. Click **Open HTML** and replace the markup with:

```html
<panel id="screen" onload="OnOpen">
    <panel class="card">
        <text class="title">Settings</text>
        <panel class="row">
            <text>Name</text>
            <input bind="playerName" style="flex-grow: 1" />
        </panel>
        <panel class="row">
            <text>Volume</text>
            <bar id="volume" bind="volume" />
            <button onclick="OnQuieter">-</button>
            <button onclick="OnLouder">+</button>
        </panel>
        <button class="primary" onclick="OnApply">Apply</button>
        <text id="status" class="hint">Press Tab to close.</text>
    </panel>
</panel>
```

The tags are `panel`, `text`, `button`, `image`, `input` and `bar`. Three attributes connect the document to code:

| Attribute | Meaning |
|---|---|
| `onclick="Name"` | Calls the method `Name` when the element is pressed. |
| `onload="Name"` | Calls the method once when the document loads. |
| `bind="field"` | Shows a public field: text for `text` and `input` (which also edits it), a 0 to 1 fill for `bar`. |

## 2. Style it

Click **Open CSS**. It creates `settings_menu.tcss` next to the document. Put this in it:

```css
#screen { width: 100%; height: 100%; align-items: center; justify-content: center; background-color: #0b0f1499 }
.card { width: 380; padding: 24; gap: 12; background-color: #1b2028f2; border-radius: 10; border-width: 1; border-color: #ffffff22 }
.title { font-size: 28; color: #ffcf5a }
.hint { font-size: 13; color: #9aa4b2 }
.row { flex-direction: row; gap: 10; align-items: center }
.primary { background-color: #2f6fb0; font-size: 18; padding: 12 16 }
#volume { flex-grow: 1; color: #5ab0ff }
```

Selectors are `#id` and `.class`. Layout is flex: `flex-direction`, `gap`, `padding`, `margin`, `width` and `height` in pixels or percent, `flex-grow`, `align-items` and `justify-content`. The preview updates as you save.

## 3. The script

Create a script named `SettingsMenu` and replace its contents, using your project's namespace:

```beef
using System;
using Tessera;

namespace MyGame;

/// Code-behind for UI/settings_menu.tui. Put this and a UI Document on the same object.
[Component]
class SettingsMenu : Component
{
    // Fields named in bind="..." must be public.
    public String playerName = new .("Player") ~ delete _;
    [Range(0, 1)] public float volume = 0.6f;

    UIDocument Document => GetComponent<UIDocument>();

    void SetStatus(StringView text)
    {
        // Find looks an element up by its id attribute.
        let status = Document.Find("status");
        if (status != null)
            status.SetText(text);
    }

    public void OnOpen() => SetStatus("Press Tab to close.");

    public void OnLouder() => volume = Mathf.Clamp01(volume + 0.1f);
    public void OnQuieter() => volume = Mathf.Clamp01(volume - 0.1f);

    public void OnApply()
    {
        SetStatus(scope $"Saved for {playerName} at volume {(int)Math.Round(volume * 100)}%.");
    }

    /// Shows or hides the whole menu.
    public void Toggle()
    {
        let screen = Document.Find("screen");
        if (screen != null)
            screen.visible = !screen.visible;
    }

    public override void Update()
    {
        if (Input.GetKeyDown(.Tab))
            Toggle();
    }
}
```

A handler takes no parameters, or one `UIElement` if it wants the element that was pressed:

```beef
public void OnPressed(UIElement button) => button.SetStyle("background-color", "#3f8f4f");
```

## 4. Put it in the scene

1. Create an empty object named `Settings Menu`.
2. Add a **UI Document** component and set **Document** to `UI/settings_menu.tui`.
3. Add the **Settings Menu** script to the same object.
4. Press **Play** and click the Game view. Type a name, press + and -, press Apply, and press Tab to hide and show the menu.

## Changing the document from code

Anything you can write in the markup you can change while the game runs:

```beef
let title = Document.Find("status");
title.SetText("Connecting...");
title.SetStyle("color", "#ff8866");
title.visible = false;
```

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| Nothing is drawn | The Document field is empty or misspelt; the Console says "UI document not found". |
| A button does nothing | The method name in `onclick` does not match a method on a component of the same object. |
| A bound value never changes | The field is not public, or its name differs from the `bind` attribute. |

For quick HUD elements without a document, override `OnGUI` on any component and call `GUI.Label`, `GUI.Button`, `GUI.Bar`, `GUI.Box`, `GUI.Toggle` or `GUI.Slider`. See [Interfaces (UI documents)](docs.php?page=ui-documents) for the full reference.
