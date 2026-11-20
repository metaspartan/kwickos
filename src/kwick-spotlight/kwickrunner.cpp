#include "kwickrunner.h"

#include <KApplicationTrader>
#include <KIO/ApplicationLauncherJob>
#include <KIO/OpenFileManagerWindowJob>
#include <KIO/OpenUrlJob>
#include <KPluginFactory>
#include <KRunner/Action>
#include <KRunner/RunnerContext>

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusReply>
#include <QDBusVariant>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QMutexLocker>
#include <QProcess>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QThreadPool>
#include <QUrl>

#include <algorithm>

K_PLUGIN_CLASS_WITH_JSON(KwickRunner, "kwickrunner.json")

using KRunner::QueryMatch;

namespace
{
const QChar ModeMark = QChar(0x1);
const QString SettingsDir = QStringLiteral("/usr/share/kwick/settings");

QString keywordsFor(const QString &page)
{
    static const QHash<QString, QString> words = {
        {QStringLiteral("Appearance"), QStringLiteral("layout theme accent colour color dark light wallpaper corner radius macos windows linux look")},
        {QStringLiteral("Dock"), QStringLiteral("taskbar launcher magnification icons panel")},
        {QStringLiteral("Effects"), QStringLiteral("animation wobbly cube glass liquid blur transparency flame minimize open close")},
        {QStringLiteral("Fonts"), QStringLiteral("typeface text size typography")},
        {QStringLiteral("Desktop Session"), QStringLiteral("kde plasma gnome hyprland sway session login")},
        {QStringLiteral("GPU"), QStringLiteral("graphics driver nvidia amd intel vulkan opengl")},
        {QStringLiteral("Gaming"), QStringLiteral("steam proton games gamemode mangohud")},
        {QStringLiteral("Storage"), QStringLiteral("disk drive partition zfs btrfs space")},
        {QStringLiteral("VPN"), QStringLiteral("wireguard openvpn tailscale network tunnel")},
        {QStringLiteral("About"), QStringLiteral("system version hardware info specs this computer")},
        {QStringLiteral("Software Update"), QStringLiteral("upgrade apt packages updates")},
    };
    return words.value(page);
}

QString vpnKind(const QString &kind)
{
    if (kind == QLatin1String("wireguard")) {
        return QStringLiteral("WireGuard");
    }
    if (kind == QLatin1String("openvpn")) {
        return QStringLiteral("OpenVPN");
    }
    return kind;
}

QString glyph(const QString &name)
{
    return QStringLiteral("/usr/share/kwick/spotlight/icons/") + name + QStringLiteral(".svg");
}

QString layoutTitle(const QString &layout)
{
    if (layout == QLatin1String("macos")) {
        return QStringLiteral("macOS");
    }
    if (layout == QLatin1String("windows")) {
        return QStringLiteral("Windows");
    }
    return QStringLiteral("Linux");
}

QDBusMessage call(const QString &service, const QString &path, const QString &iface, const QString &method, const QVariantList &args = {})
{
    QDBusMessage msg = QDBusMessage::createMethodCall(service, path, iface, method);
    msg.setArguments(args);
    return msg;
}

QStringList clipboardHistory()
{
    const QDBusReply<QStringList> reply = QDBusConnection::sessionBus().call(
        call(QStringLiteral("org.kde.klipper"), QStringLiteral("/klipper"), QStringLiteral("org.kde.klipper.klipper"), QStringLiteral("getClipboardHistoryMenu")),
        QDBus::Block,
        300);
    return reply.isValid() ? reply.value() : QStringList();
}

QString currentDesktop()
{
    const QString current = qEnvironmentVariable("XDG_CURRENT_DESKTOP").toLower();
    if (current.contains(QLatin1String("kde"))) {
        return QStringLiteral("kde");
    }
    if (current.contains(QLatin1String("gnome"))) {
        return QStringLiteral("gnome");
    }
    if (current.contains(QLatin1String("hyprland")) || qEnvironmentVariableIsSet("HYPRLAND_INSTANCE_SIGNATURE")) {
        return QStringLiteral("hyprland");
    }
    if (current.contains(QLatin1String("sway")) || qEnvironmentVariableIsSet("SWAYSOCK")) {
        return QStringLiteral("sway");
    }
    return current;
}
}

KwickRunner::KwickRunner(QObject *parent, const KPluginMetaData &metaData)
    : KRunner::AbstractRunner(parent, metaData)
    , m_files(QDir::homePath())
    , m_shared(std::make_shared<Shared>())
    , m_home(QDir::homePath())
    , m_desktop(currentDesktop())
{
    setMinLetterCount(0);
    loadPages();
    connect(this, &KRunner::AbstractRunner::prepare, this, &KwickRunner::prepareSession);
}

void KwickRunner::loadPages()
{
    QFile file(SettingsDir + QStringLiteral("/Main.qml"));
    if (!file.open(QIODevice::ReadOnly)) {
        return;
    }
    static const QRegularExpression entry(QString::fromLatin1(R"re(\{\s*name:\s*"([^"]+)"\s*,\s*icon:\s*"([^"]+)")re"));
    const QString text = QString::fromUtf8(file.readAll());
    for (auto it = entry.globalMatch(text); it.hasNext();) {
        const auto m = it.next();
        const QString svg = SettingsDir + QStringLiteral("/icons/obj-") + m.captured(2) + QStringLiteral(".svg");
        m_pages.append({m.captured(1), keywordsFor(m.captured(1)), QFileInfo::exists(svg) ? QIcon(svg) : QIcon::fromTheme(QStringLiteral("kwick-settings"))});
    }
}

void KwickRunner::prepareSession()
{
    m_files.refresh(90);
    QThreadPool::globalInstance()->start([shared = m_shared]() {
        State s;
        const QString kwick = QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation) + QStringLiteral("/kwick/");
        QFile appearance(kwick + QStringLiteral("appearance"));
        s.dark = !appearance.open(QIODevice::ReadOnly) || QString::fromUtf8(appearance.readAll()).trimmed() != QLatin1String("light");
        const QString nm = QStringLiteral("org.freedesktop.NetworkManager");
        auto prop = [&](const QString &name) {
            const QDBusReply<QDBusVariant> reply = QDBusConnection::systemBus().call(
                call(nm, QStringLiteral("/org/freedesktop/NetworkManager"), QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("Get"), {nm, name}),
                QDBus::Block,
                500);
            return reply.isValid() && reply.value().variant().toBool();
        };
        s.wifiHardware = prop(QStringLiteral("WirelessHardwareEnabled"));
        s.wifi = prop(QStringLiteral("WirelessEnabled"));
        if (!QStandardPaths::findExecutable(QStringLiteral("kwick-vpn")).isEmpty()) {
            QProcess vpn;
            vpn.start(QStringLiteral("kwick-vpn"), {QStringLiteral("list")});
            if (vpn.waitForFinished(3000)) {
                for (const QString &line : QString::fromUtf8(vpn.readAllStandardOutput()).split(QLatin1Char('\n'), Qt::SkipEmptyParts)) {
                    const QStringList cols = line.split(QLatin1Char('\t'));
                    if (!cols.value(0).isEmpty()) {
                        s.vpns.append(cols);
                    }
                }
            }
        }
        QFile layout(kwick + QStringLiteral("layout"));
        s.layout = layout.open(QIODevice::ReadOnly) ? QString::fromUtf8(layout.readAll()).trimmed() : QStringLiteral("macos");
        QMutexLocker locker(&shared->lock);
        shared->state = s;
    });
}

KwickRunner::State KwickRunner::state() const
{
    QMutexLocker locker(&m_shared->lock);
    return m_shared->state;
}

QList<KwickRunner::Command> KwickRunner::commands() const
{
    const State s = state();
    QList<Command> list = {
        {QStringLiteral("lock"), QStringLiteral("Lock Screen"), QStringLiteral("lock screen away"), glyph(QStringLiteral("lock")), {}},
        {QStringLiteral("sleep"), QStringLiteral("Sleep"), QStringLiteral("suspend sleep standby"), glyph(QStringLiteral("sleep")), {}},
        {QStringLiteral("restart"), prompts() ? QStringLiteral("Restart…") : QStringLiteral("Restart"), QStringLiteral("restart reboot"), glyph(QStringLiteral("restart")), {}},
        {QStringLiteral("shutdown"), prompts() ? QStringLiteral("Shut Down…") : QStringLiteral("Shut Down"), QStringLiteral("shut down shutdown power off poweroff turn off halt"), glyph(QStringLiteral("shutdown")), {}},
        {QStringLiteral("logout"), prompts() ? QStringLiteral("Log Out…") : QStringLiteral("Log Out"), QStringLiteral("log out logout sign out signout leave session"), glyph(QStringLiteral("logout")), {}},
        s.dark ? Command{QStringLiteral("light"), QStringLiteral("Turn On Light Mode"), QStringLiteral("light mode appearance theme bright day dark mode"), glyph(QStringLiteral("appearance")), {}}
               : Command{QStringLiteral("dark"), QStringLiteral("Turn On Dark Mode"), QStringLiteral("dark mode appearance theme night light mode"), glyph(QStringLiteral("appearance")), {}},
    };
    if (s.wifiHardware) {
        list.append(s.wifi ? Command{QStringLiteral("wifi-off"), QStringLiteral("Turn Wi-Fi Off"), QStringLiteral("wifi wi-fi wireless wlan network off disable"), glyph(QStringLiteral("wifi-off")), {}}
                           : Command{QStringLiteral("wifi-on"), QStringLiteral("Turn Wi-Fi On"), QStringLiteral("wifi wi-fi wireless wlan network on enable"), glyph(QStringLiteral("wifi")), {}});
    }
    for (const QStringList &vpn : s.vpns) {
        const bool up = vpn.value(2) == QLatin1String("connected") || vpn.value(2) == QLatin1String("connecting");
        list.append({QStringLiteral("vpn:") + vpn.value(0),
                     (up ? QStringLiteral("Disconnect VPN “%1”") : QStringLiteral("Connect VPN “%1”")).arg(vpn.value(0)),
                     QStringLiteral("vpn tunnel wireguard openvpn ") + (up ? QStringLiteral("disconnect off down ") : QStringLiteral("connect on up ")) + vpn.value(0),
                     glyph(QStringLiteral("vpn")),
                     vpnKind(vpn.value(1))});
    }
    for (const QString &layout : {QStringLiteral("macos"), QStringLiteral("windows"), QStringLiteral("linux")}) {
        if (layout != s.layout) {
            list.append({QStringLiteral("layout:") + layout,
                         QStringLiteral("Use the %1 Layout").arg(layoutTitle(layout)),
                         QStringLiteral("layout switch desktop look ") + layout + QLatin1Char(' ') + layoutTitle(layout),
                         glyph(QStringLiteral("layout")),
                         {}});
        }
    }
    return list;
}

double KwickRunner::score(const QString &query, const QString &title, const QString &keywords)
{
    const QString t = title.toLower();
    if (t == query) {
        return 1.0;
    }
    if (t.startsWith(query)) {
        return 0.9;
    }
    const QStringList words = query.split(QLatin1Char(' '), Qt::SkipEmptyParts);
    const QStringList titleWords = t.split(QRegularExpression(QStringLiteral("[\\s\\-“”]+")), Qt::SkipEmptyParts);
    const QStringList keyWords = keywords.toLower().split(QLatin1Char(' '), Qt::SkipEmptyParts);
    double worst = 1.0;
    for (const QString &w : words) {
        double best = 0.0;
        for (const QString &tw : titleWords) {
            if (tw.startsWith(w)) {
                best = 0.8;
                break;
            }
        }
        if (best == 0.0) {
            for (const QString &kw : keyWords) {
                if (kw.startsWith(w)) {
                    best = 0.7;
                    break;
                }
            }
        }
        if (best == 0.0 && w.size() >= 3 && t.contains(w)) {
            best = 0.6;
        }
        worst = std::min(worst, best);
        if (worst == 0.0) {
            return 0.0;
        }
    }
    return worst;
}

void KwickRunner::match(KRunner::RunnerContext &context)
{
    QString query = context.query();
    QChar mode;
    if (query.startsWith(ModeMark) && query.size() >= 2) {
        mode = query.at(1);
        query = query.mid(2);
    }
    query = query.trimmed().toLower();
    m_files.refresh(90);
    if (mode.isNull()) {
        const bool apps = m_desktop != QLatin1String("kde");
        if (query.size() < 2) {
            if (apps && !query.isEmpty()) {
                matchApps(context, query, true);
            }
            return;
        }
        if (apps) {
            matchApps(context, query, true);
        }
        matchPages(context, query);
        if (m_desktop == QLatin1String("gnome")) {
            matchPanels(context, query);
        }
        matchCommands(context, query, false);
        matchFiles(context, query, false);
        return;
    }
    switch (mode.unicode()) {
    case 'a':
        matchApps(context, query, false);
        break;
    case 'f':
        matchFiles(context, query, true);
        break;
    case 'x':
        matchCommands(context, query, true);
        break;
    case 'c':
        matchClipboard(context, query);
        break;
    default:
        break;
    }
}

void KwickRunner::matchPages(KRunner::RunnerContext &context, const QString &query)
{
    QList<QueryMatch> matches;
    for (const Page &page : std::as_const(m_pages)) {
        const double s = score(query, page.name, page.keywords + QStringLiteral(" kwickos settings preferences"));
        if (s <= 0.0) {
            continue;
        }
        QueryMatch m(this);
        m.setId(QStringLiteral("page:") + page.name);
        m.setText(page.name);
        m.setSubtext(QStringLiteral("KwickOS Settings"));
        m.setIcon(page.icon);
        m.setMatchCategory(QStringLiteral("System Settings"));
        m.setCategoryRelevance(s >= 0.9 ? QueryMatch::CategoryRelevance::High : QueryMatch::CategoryRelevance::Low);
        m.setRelevance(s * 0.9);
        m.setData(QVariantList{QStringLiteral("page"), page.name});
        matches.append(m);
    }
    context.addMatches(matches);
}

void KwickRunner::matchPanels(KRunner::RunnerContext &context, const QString &query)
{
    if (!m_panelsLoaded) {
        m_panelsLoaded = true;
        const KService::List panels = KApplicationTrader::query([](const KService::Ptr &service) {
            return service->categories().contains(QLatin1String("X-GNOME-Settings-Panel")) && !service->exec().isEmpty();
        });
        for (const KService::Ptr &panel : panels) {
            m_panels.append({panel->name(), panel->keywords().join(QLatin1Char(' ')) + QLatin1Char(' ') + panel->genericName(), QIcon::fromTheme(panel->icon())});
            m_panelIds.append(panel->storageId());
        }
    }
    QList<QueryMatch> matches;
    for (int i = 0; i < m_panels.size(); ++i) {
        const Page &panel = m_panels.at(i);
        const double s = score(query, panel.name, panel.keywords + QStringLiteral(" settings preferences"));
        if (s <= 0.0) {
            continue;
        }
        QueryMatch m(this);
        m.setId(QStringLiteral("panel:") + m_panelIds.at(i));
        m.setText(panel.name);
        m.setSubtext(QStringLiteral("GNOME Settings"));
        m.setIcon(panel.icon);
        m.setMatchCategory(QStringLiteral("System Settings"));
        m.setCategoryRelevance(s >= 0.9 ? QueryMatch::CategoryRelevance::High : QueryMatch::CategoryRelevance::Low);
        m.setRelevance(s * 0.86);
        m.setData(QVariantList{QStringLiteral("app"), m_panelIds.at(i)});
        matches.append(m);
    }
    context.addMatches(matches);
}

void KwickRunner::matchCommands(KRunner::RunnerContext &context, const QString &query, bool browse)
{
    QList<QueryMatch> matches;
    const QList<Command> list = commands();
    for (int i = 0; i < list.size(); ++i) {
        const Command &c = list.at(i);
        const double s = query.isEmpty() && browse ? 1.0 - i * 0.01 : score(query, c.title, c.keywords);
        if (s <= 0.0) {
            continue;
        }
        QueryMatch m(this);
        m.setId(QStringLiteral("cmd:") + c.id);
        m.setText(c.title);
        m.setSubtext(c.subtitle);
        m.setIconName(c.icon);
        m.setMatchCategory(QStringLiteral("Actions"));
        m.setCategoryRelevance(s >= 0.9 ? QueryMatch::CategoryRelevance::High : QueryMatch::CategoryRelevance::Low);
        m.setRelevance(s * 0.85);
        m.setData(QVariantList{QStringLiteral("cmd"), c.id});
        matches.append(m);
    }
    context.addMatches(matches);
}

QString KwickRunner::category(const FileIndex::Hit &hit) const
{
    if (hit.dir) {
        return QStringLiteral("Folders");
    }
    const QMimeType mime = m_mime.mimeTypeForFile(hit.name, QMimeDatabase::MatchExtension);
    const QString name = mime.name();
    if (name == QLatin1String("application/pdf")) {
        return QStringLiteral("PDF Documents");
    }
    if (name.startsWith(QLatin1String("image/"))) {
        return QStringLiteral("Images");
    }
    if (name.startsWith(QLatin1String("video/"))) {
        return QStringLiteral("Movies");
    }
    if (name.startsWith(QLatin1String("audio/"))) {
        return QStringLiteral("Music");
    }
    if (mime.inherits(QStringLiteral("application/x-executable")) || mime.inherits(QStringLiteral("application/x-shellscript"))
        || name.startsWith(QLatin1String("text/x-")) || name == QLatin1String("application/json") || name == QLatin1String("application/xml")) {
        return QStringLiteral("Developer");
    }
    if (mime.inherits(QStringLiteral("application/x-archive")) || name.contains(QLatin1String("compressed")) || name.contains(QLatin1String("zip"))
        || name.contains(QLatin1String("tar")) || name == QLatin1String("application/vnd.debian.binary-package")) {
        return QStringLiteral("Archives");
    }
    return QStringLiteral("Documents");
}

void KwickRunner::matchFiles(KRunner::RunnerContext &context, const QString &query, bool browse)
{
    if (!browse && query.size() < 2) {
        return;
    }
    m_files.ensure();
    const auto hits = browse && query.isEmpty() ? m_files.recent(40) : m_files.search(query, browse ? 60 : 24, browse);
    QList<QueryMatch> matches;
    matches.reserve(hits.size());
    const KRunner::Action reveal(QStringLiteral("reveal"), QStringLiteral("document-open-folder"), QStringLiteral("Show in Folder"));
    for (const auto &hit : hits) {
        QueryMatch m(this);
        m.setId(QStringLiteral("file:") + hit.path);
        m.setText(hit.name);
        QString parent = QFileInfo(hit.path).path();
        if (parent.startsWith(m_home)) {
            parent.replace(0, m_home.size(), QStringLiteral("~"));
        }
        m.setSubtext(parent);
        if (hit.dir) {
            m.setIconName(QStringLiteral("folder"));
        } else {
            const QMimeType mime = m_mime.mimeTypeForFile(hit.name, QMimeDatabase::MatchExtension);
            m.setIconName(QIcon::hasThemeIcon(mime.iconName()) ? mime.iconName() : mime.genericIconName());
        }
        m.setMatchCategory(browse ? QStringLiteral("Recent Files") : category(hit));
        m.setCategoryRelevance(hit.score >= 0.96 ? QueryMatch::CategoryRelevance::High : QueryMatch::CategoryRelevance::Moderate);
        m.setRelevance(hit.score * 0.8);
        m.setUrls({QUrl::fromLocalFile(hit.path)});
        m.setActions({reveal});
        m.setData(QVariantList{QStringLiteral("file"), hit.path});
        matches.append(m);
    }
    if (browse && !query.isEmpty()) {
        for (QueryMatch &m : matches) {
            m.setMatchCategory(QStringLiteral("Files"));
        }
    }
    context.addMatches(matches);
}

void KwickRunner::matchApps(KRunner::RunnerContext &context, const QString &query, bool search)
{
    KService::List apps = KApplicationTrader::query([](const KService::Ptr &service) {
        return !service->noDisplay() && !service->exec().isEmpty();
    });
    if (query.isEmpty()) {
        std::sort(apps.begin(), apps.end(), [](const KService::Ptr &a, const KService::Ptr &b) {
            return QString::localeAwareCompare(a->name(), b->name()) < 0;
        });
    }
    const double floor = search && query.size() < 2 ? 0.8 : 0.0;
    QList<QueryMatch> matches;
    for (int i = 0; i < apps.size(); ++i) {
        const KService::Ptr &app = apps.at(i);
        double s = 1.0 - i * 0.0001;
        if (!query.isEmpty()) {
            s = score(query, app->name(), app->genericName() + QLatin1Char(' ') + app->keywords().join(QLatin1Char(' ')));
            if (s <= floor) {
                continue;
            }
        }
        QueryMatch m(this);
        m.setId(QStringLiteral("app:") + app->storageId());
        m.setText(app->name());
        m.setSubtext(app->genericName());
        m.setIconName(app->icon());
        m.setMatchCategory(QStringLiteral("Applications"));
        if (search) {
            m.setCategoryRelevance(s >= 0.9 ? QueryMatch::CategoryRelevance::Highest : QueryMatch::CategoryRelevance::Moderate);
        }
        m.setRelevance(s);
        m.setData(QVariantList{QStringLiteral("app"), app->storageId()});
        matches.append(m);
    }
    context.addMatches(matches);
}

void KwickRunner::matchClipboard(KRunner::RunnerContext &context, const QString &query)
{
    const QStringList history = clipboardHistory();
    QList<QueryMatch> matches;
    for (int i = 0; i < history.size(); ++i) {
        const QString &text = history.at(i);
        if (!query.isEmpty() && !text.toLower().contains(query)) {
            continue;
        }
        QString title = text.simplified();
        if (title.size() > 120) {
            title = title.left(119) + QStringLiteral("…");
        }
        QueryMatch m(this);
        m.setId(QStringLiteral("clip:%1").arg(i));
        m.setText(title);
        m.setSubtext(text.contains(QLatin1Char('\n')) ? QStringLiteral("%1 lines").arg(text.count(QLatin1Char('\n')) + 1) : QString());
        m.setIconName(QStringLiteral("edit-paste"));
        m.setMatchCategory(QStringLiteral("Clipboard"));
        m.setRelevance(1.0 - i * 0.001);
        m.setData(QVariantList{QStringLiteral("clip"), text});
        matches.append(m);
    }
    context.addMatches(matches);
}

void KwickRunner::run(const KRunner::RunnerContext &context, const KRunner::QueryMatch &match)
{
    Q_UNUSED(context)
    const QVariantList data = match.data().toList();
    const QString kind = data.value(0).toString();
    const QString value = data.value(1).toString();
    if (kind == QLatin1String("page")) {
        QProcess::startDetached(QStringLiteral("kwick-settings"), {value.toLower()});
    } else if (kind == QLatin1String("cmd")) {
        runCommand(value);
    } else if (kind == QLatin1String("file")) {
        const QUrl url = QUrl::fromLocalFile(value);
        if (match.selectedAction().id() == QLatin1String("reveal")) {
            KIO::highlightInFileManager({url});
        } else {
            auto *job = new KIO::OpenUrlJob(url);
            job->setRunExecutables(false);
            job->start();
        }
    } else if (kind == QLatin1String("app")) {
        if (KService::Ptr service = KService::serviceByStorageId(value)) {
            (new KIO::ApplicationLauncherJob(service))->start();
        }
    } else if (kind == QLatin1String("clip")) {
        QDBusConnection::sessionBus().asyncCall(
            call(QStringLiteral("org.kde.klipper"), QStringLiteral("/klipper"), QStringLiteral("org.kde.klipper.klipper"), QStringLiteral("setClipboardContents"), {value}));
    }
}

bool KwickRunner::prompts() const
{
    return m_desktop == QLatin1String("kde") || m_desktop == QLatin1String("gnome");
}

void KwickRunner::runCommand(const QString &id)
{
    const QString prompt = QStringLiteral("org.kde.LogoutPrompt");
    const QString gnome = QStringLiteral("org.gnome.SessionManager");
    const bool kde = m_desktop == QLatin1String("kde");
    const bool isGnome = m_desktop == QLatin1String("gnome");
    auto session = [](const QDBusMessage &msg) {
        QDBusConnection::sessionBus().asyncCall(msg);
    };
    auto logind = [](const QString &method) {
        QDBusConnection::systemBus().asyncCall(
            call(QStringLiteral("org.freedesktop.login1"), QStringLiteral("/org/freedesktop/login1"), QStringLiteral("org.freedesktop.login1.Manager"), method, {true}));
    };
    auto gnomeSession = [&](const QString &method, const QVariantList &args = {}) {
        session(call(gnome, QStringLiteral("/org/gnome/SessionManager"), gnome, method, args));
    };
    if (id == QLatin1String("lock")) {
        if (kde) {
            session(call(QStringLiteral("org.freedesktop.ScreenSaver"), QStringLiteral("/ScreenSaver"), QStringLiteral("org.freedesktop.ScreenSaver"), QStringLiteral("Lock")));
        } else if (isGnome) {
            session(call(QStringLiteral("org.gnome.ScreenSaver"), QStringLiteral("/org/gnome/ScreenSaver"), QStringLiteral("org.gnome.ScreenSaver"), QStringLiteral("Lock")));
        } else if (!QStandardPaths::findExecutable(QStringLiteral("swaylock")).isEmpty()) {
            QProcess::startDetached(QStringLiteral("swaylock"), {QStringLiteral("-f")});
        } else {
            QProcess::startDetached(QStringLiteral("loginctl"), {QStringLiteral("lock-session")});
        }
    } else if (id == QLatin1String("sleep")) {
        logind(QStringLiteral("Suspend"));
    } else if (id == QLatin1String("restart")) {
        if (kde) {
            session(call(prompt, QStringLiteral("/LogoutPrompt"), prompt, QStringLiteral("promptReboot")));
        } else if (isGnome) {
            gnomeSession(QStringLiteral("Reboot"));
        } else {
            logind(QStringLiteral("Reboot"));
        }
    } else if (id == QLatin1String("shutdown")) {
        if (kde) {
            session(call(prompt, QStringLiteral("/LogoutPrompt"), prompt, QStringLiteral("promptShutDown")));
        } else if (isGnome) {
            gnomeSession(QStringLiteral("Shutdown"));
        } else {
            logind(QStringLiteral("PowerOff"));
        }
    } else if (id == QLatin1String("logout")) {
        if (kde) {
            session(call(prompt, QStringLiteral("/LogoutPrompt"), prompt, QStringLiteral("promptLogout")));
        } else if (isGnome) {
            gnomeSession(QStringLiteral("Logout"), {QVariant::fromValue(0u)});
        } else if (m_desktop == QLatin1String("hyprland")) {
            QProcess::startDetached(QStringLiteral("hyprctl"), {QStringLiteral("dispatch"), QStringLiteral("exit")});
        } else if (m_desktop == QLatin1String("sway")) {
            QProcess::startDetached(QStringLiteral("swaymsg"), {QStringLiteral("exit")});
        }
    } else if (id == QLatin1String("light") || id == QLatin1String("dark")) {
        QProcess::startDetached(QStringLiteral("kwick-layout"), {QStringLiteral("appearance"), id});
    } else if (id.startsWith(QLatin1String("wifi-"))) {
        const QString nm = QStringLiteral("org.freedesktop.NetworkManager");
        QDBusConnection::systemBus().asyncCall(call(nm,
                                                    QStringLiteral("/org/freedesktop/NetworkManager"),
                                                    QStringLiteral("org.freedesktop.DBus.Properties"),
                                                    QStringLiteral("Set"),
                                                    {nm, QStringLiteral("WirelessEnabled"), QVariant::fromValue(QDBusVariant(id == QLatin1String("wifi-on")))}));
    } else if (id.startsWith(QLatin1String("vpn:"))) {
        QProcess::startDetached(QStringLiteral("kwick-vpn"), {QStringLiteral("toggle"), id.mid(4)});
    } else if (id.startsWith(QLatin1String("layout:"))) {
        QProcess::startDetached(QStringLiteral("kwick-layout"), {id.mid(7)});
    }
}

#include "kwickrunner.moc"
