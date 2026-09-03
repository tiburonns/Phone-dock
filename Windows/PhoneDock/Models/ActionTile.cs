using System.Text.Json.Nodes;
using PhoneDock.Core;

namespace PhoneDock.Models;

public sealed record ActionTile
{
    public string Id { get; init; } = Guid.NewGuid().ToString().ToUpperInvariant();
    public string Title { get; set; } = AppLanguage.T("Nueva acción");
    public string Kind { get; set; } = "app";
    public string Target { get; set; } = "";
    public string Emoji { get; set; } = "";
    public string Tint { get; set; } = "6650D8";
    public string? Icon { get; set; }
    public int Page { get; set; }
    public string Subtitle => AppLanguage.T(Kind switch { "app" => "Aplicación", "website" => "Sitio web", _ => "Texto" });
    public JsonObject ToWire(int order) {
        var tile = new JsonObject {
            ["id"] = Id, ["title"] = Title, ["subtitle"] = Subtitle,
            ["systemImage"] = Kind == "website" ? "globe" : Kind == "app" ? "app.fill" : "text.bubble.fill",
            ["tintHex"] = Tint, ["kind"] = Kind == "text" ? "emoji" : Kind,
            ["page"] = Page, ["sortOrder"] = order,
            ["command"] = Kind switch {
                "website" => Wire.ValueCommand("openURL", JsonValue.Create(Target)!),
                "text" => Wire.ValueCommand("insertText", JsonValue.Create(Target)!),
                _ => Wire.Command("launchApp", new() { ["bundleIdentifier"] = Id })
            }
        };
        if (!string.IsNullOrEmpty(Emoji)) tile["displayEmoji"] = Emoji;
        if (Icon != null) tile["iconPNGData"] = Icon;
        return tile;
    }
}

public sealed record Preferences
{
    public string Language { get; set; } = "system";
    public string Palette { get; set; } = "Aurora";
    public bool Dark { get; set; }
    public bool LargeIcons { get; set; } = true;
    public bool SoftCorners { get; set; } = true;
}
