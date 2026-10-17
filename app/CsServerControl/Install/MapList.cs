using System.IO;
using System.Text;

namespace CsServerControl.Install;

/// <summary>One row of tools\maps.csv. ModId names the GameBanana page and may be empty.</summary>
internal sealed record MapListEntry(string Name, string Url, string ArchiveName, string ModId);

/// <summary>Reads tools\maps.csv (Name,Url,ArchiveName,ModId with a header line).</summary>
internal static class MapList {
    public static IReadOnlyList<MapListEntry> Load(string path) {
        return Parse(File.ReadAllLines(path));
    }

    public static IReadOnlyList<MapListEntry> Parse(IEnumerable<string> lines) {
        List<MapListEntry> entries = [];
        List<string>? header = null;
        foreach (string line in lines) {
            if (string.IsNullOrWhiteSpace(line)) {
                continue;
            }

            List<string> fields = SplitFields(line);
            if (header == null) {
                header = fields;
                continue;
            }

            string name = FieldOf(header, fields, "Name");
            if (name.Length == 0) {
                continue;
            }
            entries.Add(new MapListEntry(
                name,
                FieldOf(header, fields, "Url"),
                FieldOf(header, fields, "ArchiveName"),
                FieldOf(header, fields, "ModId")));
        }
        return entries;
    }

    // Columns are found by their header name, like Import-Csv did, so the
    // order in the file does not matter and a missing column reads as empty.
    private static string FieldOf(List<string> header, List<string> fields, string column) {
        int index = header.FindIndex(name => name.Equals(column, StringComparison.OrdinalIgnoreCase));
        if (index < 0 || index >= fields.Count) {
            return "";
        }
        return fields[index].Trim();
    }

    /// <summary>Splits one CSV line; a quoted field may hold commas and doubled quotes.</summary>
    internal static List<string> SplitFields(string line) {
        List<string> fields = [];
        var current = new StringBuilder();
        bool inQuotes = false;
        for (int index = 0; index < line.Length; index++) {
            char character = line[index];
            if (inQuotes) {
                bool isEscapedQuote = character == '"' && index + 1 < line.Length && line[index + 1] == '"';
                if (isEscapedQuote) {
                    current.Append('"');
                    index++;
                } else if (character == '"') {
                    inQuotes = false;
                } else {
                    current.Append(character);
                }
                continue;
            }

            if (character == '"') {
                inQuotes = true;
            } else if (character == ',') {
                fields.Add(current.ToString());
                current.Clear();
            } else {
                current.Append(character);
            }
        }
        fields.Add(current.ToString());
        return fields;
    }
}
