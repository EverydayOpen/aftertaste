# Security

Please report vulnerabilities privately: this repository's **Security** tab › **Report a vulnerability**. Don't open a public issue.

- **Supported version:** the latest release, the one the website's download page links to.
- **Response:** an acknowledgement within 7 days, and a fix or a plan within 30 days after that.
- **In scope:** the Aftertaste app, the website, and this repository's GitHub Actions workflows.
- **Especially welcome:** any way to make Aftertaste move an item it should not, such as one that belongs to an app that is
  still installed, a symlink or mount point that leads outside the folders it reads, an item that changed between the scan and
  the move, or anything on the never-list (Apple's own data, iCloud folders, Mail, Messages, Photos, Keychains, its own data);
  any way to make it delete, overwrite, copy, rename or change a file's permissions; any way to make Undo overwrite something;
  and any path by which a file name, a path or an app list could leave the Mac or reach the Trace Report when "Hide app names"
  is on.
- **Not a vulnerability:** a matching rule that is too cautious or too eager. Use the "Report a wrong match" issue form for
  that, and never paste file contents into it.

Aftertaste makes no network connections and needs no permission, so a report about it "phoning home", needing elevated
rights or a privileged helper would itself be a bug worth reporting.
