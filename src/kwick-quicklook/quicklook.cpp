#include "quicklook.h"
#include "previews.h"

#include <KApplicationTrader>
#include <KConfigGroup>
#include <KFormat>
#include <KIO/OpenFileManagerWindowJob>
#include <KIO/OpenUrlJob>
#include <KSharedConfig>

#include <archive.h>
#include <archive_entry.h>

#include <QClipboard>
#include <QCollator>
#include <QCryptographicHash>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDateTime>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileSystemWatcher>
#include <QGuiApplication>
#include <QIcon>
#include <QImageReader>
#include <QLocale>
#include <QMimeData>
#include <QProcess>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQuickItem>
#include <QQuickView>
#include <QScreen>
#include <QStandardPaths>
#include <QTextBlock>
#include <QTextCursor>
#include <QTextDocument>
#include <QTextList>
#include <QTextTable>
#include <QTimer>

#include <poppler-qt6.h>

#include <algorithm>

namespace
{
QString kwickFile(const QString &name)
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation) + QStringLiteral("/kwick/") + name;
}

QString readKwick(const QString &name)
{
    QFile file(kwickFile(name));
    return file.open(QIODevice::ReadOnly) ? QString::fromUtf8(file.readAll()).trimmed() : QString();
}

QString iconThemeFor(const QString &layout)
{
    if (layout == QLatin1String("windows")) {
        return QStringLiteral("KwickOS-Fluent");
    }
    if (layout == QLatin1String("linux")) {
        return QStringLiteral("KwickOS-Linux");
    }
    return QStringLiteral("KwickOS");
}

bool isOffice(const QString &mime)
{
    return mime.startsWith(QLatin1String("application/vnd.oasis.opendocument")) || mime.startsWith(QLatin1String("application/vnd.openxmlformats"))
        || mime == QLatin1String("application/msword") || mime == QLatin1String("application/vnd.ms-excel")
        || mime == QLatin1String("application/vnd.ms-powerpoint") || mime == QLatin1String("application/rtf") || mime == QLatin1String("text/rtf");
}

bool isArchive(const QMimeType &type)
{
    static const QStringList kinds = {
        QStringLiteral("application/zip"), QStringLiteral("application/x-tar"), QStringLiteral("application/x-compressed-tar"),
        QStringLiteral("application/x-bzip-compressed-tar"), QStringLiteral("application/x-xz-compressed-tar"), QStringLiteral("application/x-zstd-compressed-tar"),
        QStringLiteral("application/x-7z-compressed"), QStringLiteral("application/vnd.rar"), QStringLiteral("application/x-rar"),
        QStringLiteral("application/vnd.debian.binary-package"), QStringLiteral("application/x-iso9660-image"), QStringLiteral("application/java-archive"),
        QStringLiteral("application/x-cpio"), QStringLiteral("application/x-lzma-compressed-tar"), QStringLiteral("application/x-archive"),
        QStringLiteral("application/vnd.android.package-archive"), QStringLiteral("application/x-rpm"),
    };
    for (const QString &k : kinds) {
        if (type.inherits(k)) {
            return true;
        }
    }
    return false;
}

bool isText(const QMimeType &type)
{
    if (type.inherits(QStringLiteral("text/plain"))) {
        return true;
    }
    static const QStringList kinds = {
        QStringLiteral("application/json"), QStringLiteral("application/xml"), QStringLiteral("application/x-shellscript"),
        QStringLiteral("application/javascript"), QStringLiteral("application/toml"), QStringLiteral("application/x-yaml"),
        QStringLiteral("application/sql"), QStringLiteral("application/x-desktop"), QStringLiteral("application/x-perl"),
        QStringLiteral("application/x-php"), QStringLiteral("application/x-ruby"), QStringLiteral("application/x-wine-extension-ini"),
    };
    for (const QString &k : kinds) {
        if (type.inherits(k)) {
            return true;
        }
    }
    return false;
}

QString when(const QDateTime &time)
{
    const QDate today = QDate::currentDate();
    const QString clock = QLocale().toString(time.time(), QLocale::ShortFormat);
    if (time.date() == today) {
        return QStringLiteral("Today at ") + clock;
    }
    if (time.date() == today.addDays(-1)) {
        return QStringLiteral("Yesterday at ") + clock;
    }
    return QLocale().toString(time.date(), QStringLiteral("MMM d, yyyy")) + QStringLiteral(" at ") + clock;
}

QString markdownHtml(const QString &markdown, bool dark, const QColor &accent)
{
    QTextDocument doc;
    doc.setMarkdown(markdown);
    const QColor sub = dark ? QColor(255, 255, 255, 140) : QColor(0, 0, 0, 128);
    const QColor codeBg = dark ? QColor(255, 255, 255, 22) : QColor(0, 0, 0, 14);
    const QColor rule = dark ? QColor(255, 255, 255, 40) : QColor(0, 0, 0, 36);
    QTextCursor cursor(&doc);
    for (QTextBlock block = doc.begin(); block.isValid(); block = block.next()) {
        QTextBlockFormat fmt = block.blockFormat();
        const int level = fmt.headingLevel();
        const bool quote = fmt.property(QTextFormat::BlockQuoteLevel).toInt() > 0;
        const bool code = fmt.property(QTextFormat::BlockCodeFence).isValid() || fmt.nonBreakableLines();
        if (level > 0) {
            fmt.setTopMargin(level <= 2 ? 22 : 16);
            fmt.setBottomMargin(8);
        } else if (block.textList()) {
            fmt.setTopMargin(2);
            fmt.setBottomMargin(2);
        } else {
            fmt.setTopMargin(0);
            fmt.setBottomMargin(12);
        }
        if (quote) {
            fmt.setLeftMargin(18);
        }
        if (code) {
            fmt.setBackground(codeBg);
            fmt.setLeftMargin(12);
            fmt.setBottomMargin(0);
        }
        fmt.setLineHeight(135, QTextBlockFormat::ProportionalHeight);
        cursor.setPosition(block.position());
        cursor.setBlockFormat(fmt);
        for (QTextBlock::iterator it = block.begin(); !it.atEnd(); ++it) {
            const QTextFragment frag = it.fragment();
            if (!frag.isValid()) {
                continue;
            }
            QTextCharFormat cf = frag.charFormat();
            bool touched = false;
            if (cf.fontFixedPitch() || code) {
                cf.setBackground(codeBg);
                cf.setFontFamilies({QStringLiteral("JetBrains Mono")});
                cf.setFontPointSize(cf.fontPointSize() > 0 ? cf.fontPointSize() * 0.92 : 10.5);
                touched = true;
            }
            if (cf.isAnchor()) {
                cf.setForeground(accent);
                cf.setFontUnderline(false);
                touched = true;
            }
            if (quote) {
                cf.setForeground(sub);
                touched = true;
            }
            if (touched) {
                QTextCursor c(&doc);
                c.setPosition(frag.position());
                c.setPosition(frag.position() + frag.length(), QTextCursor::KeepAnchor);
                c.setCharFormat(cf);
            }
        }
    }
    for (QTextFrame::iterator it = doc.rootFrame()->begin(); !it.atEnd(); ++it) {
        if (auto *table = qobject_cast<QTextTable *>(it.currentFrame())) {
            QTextTableFormat tf = table->format();
            tf.setCellPadding(7);
            tf.setCellSpacing(0);
            tf.setBorder(1);
            tf.setBorderBrush(rule);
            tf.setBorderStyle(QTextFrameFormat::BorderStyle_Solid);
            tf.setBorderCollapse(true);
            tf.setBottomMargin(14);
            table->setFormat(tf);
        }
    }
    return doc.toHtml();
}

QString cacheDir()
{
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::GenericCacheLocation) + QStringLiteral("/kwick/quicklook");
    QDir().mkpath(dir);
    return dir;
}
}

QuickLook::QuickLook(QObject *parent)
    : QObject(parent)
{
    refreshTheme();
    QDir().mkpath(kwickFile(QString()));
    m_watcher = new QFileSystemWatcher(this);
    m_watcher->addPath(kwickFile(QString()));
    for (const QString &f : {QStringLiteral("appearance"), QStringLiteral("layout"), QStringLiteral("radius")}) {
        if (QFile::exists(kwickFile(f))) {
            m_watcher->addPath(kwickFile(f));
        }
    }
    connect(m_watcher, &QFileSystemWatcher::directoryChanged, this, &QuickLook::refreshTheme);
    connect(m_watcher, &QFileSystemWatcher::fileChanged, this, &QuickLook::refreshTheme);
}

QuickLook::~QuickLook()
{
    delete m_view;
}

void QuickLook::refreshTheme()
{
    const bool dark = readKwick(QStringLiteral("appearance")) != QLatin1String("light");
    QString layout = readKwick(QStringLiteral("layout"));
    if (layout.isEmpty()) {
        layout = QStringLiteral("macos");
    }
    bool numeric = false;
    int radius = readKwick(QStringLiteral("radius")).toInt(&numeric);
    if (!numeric) {
        radius = 10;
    }
    KSharedConfig::Ptr globals = KSharedConfig::openConfig(QStringLiteral("kdeglobals"));
    globals->reparseConfiguration();
    const QString raw = KConfigGroup(globals, QStringLiteral("General")).readEntry("AccentColor", QString()).trimmed();
    const QStringList channels = raw.split(QLatin1Char(','));
    QColor accent;
    if (channels.size() >= 3) {
        accent = QColor(channels.at(0).trimmed().toInt(), channels.at(1).trimmed().toInt(), channels.at(2).trimmed().toInt());
    } else if (QColor::isValidColorName(raw)) {
        accent = QColor::fromString(raw);
    }
    if (!accent.isValid()) {
        accent = dark ? QColor(QStringLiteral("#0a84ff")) : QColor(QStringLiteral("#007aff"));
    }
    if (!qEnvironmentVariable("XDG_CURRENT_DESKTOP").contains(QLatin1String("KDE"), Qt::CaseInsensitive) && layout != m_layout) {
        QIcon::setThemeName(iconThemeFor(layout));
    }
    m_dark = dark;
    m_layout = layout;
    m_radius = radius;
    m_accent = accent;
    Q_EMIT themeChanged();
}

QString QuickLook::path() const
{
    return m_files.value(m_index);
}

QString QuickLook::url() const
{
    return m_index >= 0 ? QUrl::fromLocalFile(path()).toString() : QString();
}

QString QuickLook::name() const
{
    return QFileInfo(path()).fileName();
}

bool QuickLook::shown() const
{
    return m_view && m_view->isVisible();
}

void QuickLook::createView()
{
    if (m_view) {
        return;
    }
    m_view = new QQuickView();
    m_view->setTitle(QStringLiteral("Quick Look"));
    m_view->setResizeMode(QQuickView::SizeRootObjectToView);
    m_view->setColor(m_dark ? QColor(30, 30, 30) : QColor(245, 245, 245));
    m_view->setMinimumSize(QSize(360, 240));
    connect(this, &QuickLook::themeChanged, m_view, [this]() {
        m_view->setColor(m_dark ? QColor(30, 30, 30) : QColor(245, 245, 245));
    });
    QQmlEngine *engine = m_view->engine();
    engine->addImageProvider(QStringLiteral("pdf"), new PdfProvider);
    engine->addImageProvider(QStringLiteral("icon"), new IconProvider);
    engine->addImageProvider(QStringLiteral("glyph"), new GlyphProvider);
    m_view->rootContext()->setContextProperty(QStringLiteral("ql"), this);
    m_view->loadFromModule(QStringLiteral("KwickQuickLook"), QStringLiteral("Main"));
    connect(m_view, &QWindow::visibleChanged, this, [this](bool visible) {
        Q_EMIT shownChanged();
        Q_EMIT visibleChanged(visible);
        if (!visible) {
            m_expanded = false;
            resetContent();
            m_index = -1;
            m_files.clear();
            Q_EMIT currentChanged();
            Q_EMIT contentChanged();
        }
    });
}

void QuickLook::show(const QStringList &files, int index, const QString &host)
{
    QStringList clean;
    for (const QString &f : files) {
        const QUrl u = f.contains(QLatin1String("://")) ? QUrl(f) : QUrl::fromLocalFile(QFileInfo(f).absoluteFilePath());
        if (u.isLocalFile() && QFileInfo::exists(u.toLocalFile())) {
            clean.append(QFileInfo(u.toLocalFile()).absoluteFilePath());
        }
    }
    if (clean.isEmpty()) {
        return;
    }
    m_files = clean;
    m_host = host;
    m_index = std::clamp(index, 0, int(clean.size()) - 1);
    createView();
    load();
    if (!m_view->isVisible()) {
        m_view->show();
    }
    m_view->requestActivate();
    m_view->raise();
}

void QuickLook::showUri(const QString &uri, bool closeIfShown)
{
    const QUrl u(uri);
    if (closeIfShown && shown() && u.isLocalFile() && u.toLocalFile() == path()) {
        close();
        return;
    }
    show({uri}, 0, QStringLiteral("nautilus"));
}

void QuickLook::close()
{
    if (m_view) {
        if (m_view->visibility() == QWindow::FullScreen) {
            m_view->showNormal();
        }
        m_view->hide();
    }
}

void QuickLook::resetContent()
{
    ++m_serial;
    if (m_converter) {
        m_converter->kill();
    }
    m_text.clear();
    m_truncated = false;
    m_entries.clear();
    m_summary.clear();
    m_pdf.clear();
    m_pages = 0;
    m_pageSize = QSizeF();
    m_imageSize = QSize();
    m_busy = false;
}

void QuickLook::load()
{
    resetContent();
    const QFileInfo info(path());
    const QMimeType type = m_db.mimeTypeForFile(info);
    m_mime = type.name();
    m_icon = QIcon::hasThemeIcon(type.iconName()) ? type.iconName() : type.genericIconName();
    m_appName.clear();
    m_appId.clear();
    if (info.isDir()) {
        m_kind = QStringLiteral("folder");
        m_icon = QStringLiteral("folder");
        m_appName = QStringLiteral("Files");
        readFolder();
    } else if (type.name().startsWith(QLatin1String("image/"))) {
        QImageReader reader(info.filePath());
        reader.setAutoTransform(true);
        m_imageSize = reader.size();
        if (reader.transformation() & QImageIOHandler::TransformationRotate90) {
            m_imageSize.transpose();
        }
        m_kind = reader.supportsAnimation() && reader.imageCount() > 1 ? QStringLiteral("animation") : QStringLiteral("image");
    } else if (type.name().startsWith(QLatin1String("video/"))) {
        m_kind = QStringLiteral("video");
    } else if (type.name().startsWith(QLatin1String("audio/"))) {
        m_kind = QStringLiteral("audio");
    } else if (type.inherits(QStringLiteral("application/pdf"))) {
        m_kind = QStringLiteral("pdf");
        readPdf(info.filePath());
    } else if (type.name().startsWith(QLatin1String("font/")) || type.inherits(QStringLiteral("application/x-font-ttf")) || type.inherits(QStringLiteral("application/x-font-otf"))) {
        m_kind = QStringLiteral("font");
    } else if (type.inherits(QStringLiteral("text/markdown"))) {
        m_kind = QStringLiteral("markdown");
        readText(512 * 1024);
        m_text = markdownHtml(m_text, m_dark, m_accent);
    } else if (isArchive(type)) {
        m_kind = QStringLiteral("archive");
        readArchive();
    } else if (isOffice(type.name())) {
        m_kind = QStringLiteral("office");
        convertOffice();
    } else if (isText(type) || info.size() == 0) {
        m_kind = QStringLiteral("text");
        readText(1024 * 1024);
    } else {
        m_kind = QStringLiteral("info");
        QFile probe(info.filePath());
        if (info.size() < 4 * 1024 * 1024 && probe.open(QIODevice::ReadOnly) && !probe.read(8192).contains('\0')) {
            m_kind = QStringLiteral("text");
            readText(1024 * 1024);
        }
    }
    if (m_appName.isEmpty()) {
        if (KService::Ptr app = KApplicationTrader::preferredService(m_mime)) {
            m_appName = app->name();
            m_appId = app->storageId();
        }
    }
    QStringList parts;
    parts << (info.isDir() ? QStringLiteral("Folder") : type.comment());
    if (!info.isDir()) {
        parts << KFormat().formatByteSize(info.size(), 1, KFormat::JEDECBinaryDialect);
    }
    if (m_imageSize.isValid()) {
        parts << QStringLiteral("%1 × %2").arg(m_imageSize.width()).arg(m_imageSize.height());
    }
    parts << QStringLiteral("Modified ") + when(info.lastModified());
    m_details = parts.join(QStringLiteral("  ·  "));
    if (m_view) {
        m_view->setTitle(info.fileName());
    }
    Q_EMIT currentChanged();
    Q_EMIT contentChanged();
}

void QuickLook::readText(qint64 limit)
{
    QFile file(path());
    if (!file.open(QIODevice::ReadOnly)) {
        return;
    }
    QByteArray data = file.read(limit + 1);
    m_truncated = data.size() > limit;
    if (m_truncated) {
        data.truncate(limit);
    }
    m_text = QString::fromUtf8(data);
}

void QuickLook::readArchive()
{
    struct archive *a = archive_read_new();
    archive_read_support_filter_all(a);
    archive_read_support_format_all(a);
    QVariantList entries;
    qint64 total = 0;
    int files = 0;
    int folders = 0;
    if (archive_read_open_filename(a, QFile::encodeName(path()).constData(), 65536) == ARCHIVE_OK) {
        struct archive_entry *entry;
        while (archive_read_next_header(a, &entry) == ARCHIVE_OK) {
            const QString name = QString::fromUtf8(archive_entry_pathname_utf8(entry) ? archive_entry_pathname_utf8(entry) : archive_entry_pathname(entry));
            const bool dir = archive_entry_filetype(entry) == AE_IFDIR;
            const qint64 size = archive_entry_size(entry);
            dir ? ++folders : ++files;
            total += std::max<qint64>(0, size);
            if (entries.size() < 5000) {
                const int depth = name.count(QLatin1Char('/')) - (name.endsWith(QLatin1Char('/')) ? 1 : 0);
                QString shown = name;
                if (shown.endsWith(QLatin1Char('/'))) {
                    shown.chop(1);
                }
                entries.append(QVariantMap{
                    {QStringLiteral("name"), shown.section(QLatin1Char('/'), -1)},
                    {QStringLiteral("depth"), depth},
                    {QStringLiteral("dir"), dir},
                    {QStringLiteral("size"), dir ? QString() : KFormat().formatByteSize(size, 1, KFormat::JEDECBinaryDialect)},
                    {QStringLiteral("icon"), dir ? QStringLiteral("folder") : m_db.mimeTypeForFile(name, QMimeDatabase::MatchExtension).iconName()},
                });
            }
            archive_read_data_skip(a);
        }
    }
    archive_read_free(a);
    m_entries = entries;
    m_summary = QStringLiteral("%1 %2, %3 %4  ·  %5 uncompressed")
                    .arg(files)
                    .arg(files == 1 ? QStringLiteral("file") : QStringLiteral("files"))
                    .arg(folders)
                    .arg(folders == 1 ? QStringLiteral("folder") : QStringLiteral("folders"))
                    .arg(KFormat().formatByteSize(total, 1, KFormat::JEDECBinaryDialect));
}

void QuickLook::readFolder()
{
    QDir dir(path());
    const QFileInfoList list = dir.entryInfoList(QDir::AllEntries | QDir::NoDotAndDotDot, QDir::DirsFirst | QDir::Name | QDir::IgnoreCase);
    QVariantList entries;
    qint64 total = 0;
    for (const QFileInfo &f : list) {
        if (!f.isDir()) {
            total += f.size();
        }
        if (entries.size() < 2000 && !f.isHidden()) {
            const QMimeType t = m_db.mimeTypeForFile(f, QMimeDatabase::MatchExtension);
            entries.append(QVariantMap{
                {QStringLiteral("name"), f.fileName()},
                {QStringLiteral("depth"), 0},
                {QStringLiteral("dir"), f.isDir()},
                {QStringLiteral("size"), f.isDir() ? QString() : KFormat().formatByteSize(f.size(), 1, KFormat::JEDECBinaryDialect)},
                {QStringLiteral("icon"), f.isDir() ? QStringLiteral("folder") : t.iconName()},
            });
        }
    }
    m_entries = entries;
    m_summary = QStringLiteral("%1 %2  ·  %3").arg(list.size()).arg(list.size() == 1 ? QStringLiteral("item") : QStringLiteral("items")).arg(KFormat().formatByteSize(total, 1, KFormat::JEDECBinaryDialect));
}

void QuickLook::readPdf(const QString &file)
{
    std::unique_ptr<Poppler::Document> doc = Poppler::Document::load(file);
    if (!doc || doc->isLocked()) {
        m_kind = QStringLiteral("info");
        return;
    }
    m_pages = doc->numPages();
    if (std::unique_ptr<Poppler::Page> first = doc->page(0)) {
        m_pageSize = first->pageSizeF();
    }
    m_pdf = file;
}

void QuickLook::convertOffice()
{
    const QString soffice = QStandardPaths::findExecutable(QStringLiteral("soffice"));
    if (soffice.isEmpty()) {
        m_kind = QStringLiteral("info");
        return;
    }
    const QFileInfo info(path());
    const QByteArray key = QCryptographicHash::hash((info.absoluteFilePath() + QString::number(info.lastModified().toMSecsSinceEpoch())).toUtf8(), QCryptographicHash::Sha1).toHex();
    const QString dir = cacheDir() + QLatin1Char('/') + QString::fromLatin1(key);
    const QString pdf = dir + QLatin1Char('/') + info.completeBaseName() + QStringLiteral(".pdf");
    if (QFile::exists(pdf)) {
        readPdf(pdf);
        return;
    }
    m_busy = true;
    QDir().mkpath(dir);
    auto *proc = new QProcess(this);
    m_converter = proc;
    const int serial = m_serial;
    connect(proc, &QProcess::finished, this, [this, proc, pdf, serial]() {
        proc->deleteLater();
        if (serial != m_serial) {
            return;
        }
        m_busy = false;
        if (QFile::exists(pdf)) {
            readPdf(pdf);
        } else {
            m_kind = QStringLiteral("info");
            Q_EMIT currentChanged();
        }
        Q_EMIT contentChanged();
    });
    proc->start(soffice, {QStringLiteral("--headless"), QStringLiteral("-env:UserInstallation=file://") + cacheDir() + QStringLiteral("/profile"), QStringLiteral("--convert-to"), QStringLiteral("pdf"), QStringLiteral("--outdir"), dir, info.absoluteFilePath()});
}

void QuickLook::siblings()
{
    const QFileInfo info(path());
    QDir dir = info.dir();
    QFileInfoList list = dir.entryInfoList(QDir::AllEntries | QDir::NoDotAndDotDot);
    QCollator collator;
    collator.setNumericMode(true);
    collator.setCaseSensitivity(Qt::CaseInsensitive);
    std::sort(list.begin(), list.end(), [&collator](const QFileInfo &a, const QFileInfo &b) {
        if (a.isDir() != b.isDir()) {
            return a.isDir();
        }
        return collator.compare(a.fileName(), b.fileName()) < 0;
    });
    QStringList files;
    for (const QFileInfo &f : list) {
        if (!f.isHidden() || f.absoluteFilePath() == info.absoluteFilePath()) {
            files.append(f.absoluteFilePath());
        }
    }
    const int at = files.indexOf(info.absoluteFilePath());
    if (at >= 0) {
        m_files = files;
        m_index = at;
    }
}

void QuickLook::step(int delta, int direction)
{
    if (m_host == QLatin1String("nautilus")) {
        Q_EMIT selectionEvent(uint(direction));
        return;
    }
    if (m_host.startsWith(QLatin1String("dolphin:"))) {
        QDBusMessage msg = QDBusMessage::createMethodCall(m_host.mid(8), QStringLiteral("/org/kwickos/QuickLookHost"), QStringLiteral("org.kwickos.QuickLookHost"), QStringLiteral("Step"));
        msg.setArguments({direction});
        const QDBusMessage reply = QDBusConnection::sessionBus().call(msg, QDBus::Block, 500);
        if (reply.type() == QDBusMessage::ReplyMessage && reply.arguments().value(0).toBool()) {
            return;
        }
    }
    if (m_files.size() == 1) {
        siblings();
    }
    const int next = m_index + delta;
    if (next < 0 || next >= m_files.size()) {
        return;
    }
    m_index = next;
    load();
}

void QuickLook::open()
{
    if (m_index < 0) {
        return;
    }
    auto *job = new KIO::OpenUrlJob(QUrl::fromLocalFile(path()));
    job->setRunExecutables(false);
    job->start();
    close();
}

void QuickLook::reveal()
{
    if (m_index >= 0) {
        KIO::highlightInFileManager({QUrl::fromLocalFile(path())});
        close();
    }
}

void QuickLook::share()
{
    if (m_index < 0) {
        return;
    }
    QProcess::startDetached(QStringLiteral("kwick-nearby"), {QStringLiteral("--share"), path()});
}

void QuickLook::copyPath()
{
    if (m_index < 0) {
        return;
    }
    auto *data = new QMimeData;
    data->setUrls({QUrl::fromLocalFile(path())});
    data->setText(path());
    QGuiApplication::clipboard()->setMimeData(data);
}

void QuickLook::toggleFullScreen()
{
    if (!m_view) {
        return;
    }
    if (m_view->visibility() == QWindow::FullScreen) {
        m_view->showNormal();
    } else {
        m_view->showFullScreen();
    }
}

void QuickLook::fit(qreal width, qreal height, bool keepAspect)
{
    if (!m_view || m_view->visibility() == QWindow::FullScreen || m_expanded) {
        return;
    }
    QScreen *screen = m_view->screen() ? m_view->screen() : QGuiApplication::primaryScreen();
    const QSize avail = screen->availableSize();
    const int maxW = int(avail.width() * 0.72);
    const int maxH = int(avail.height() * 0.8);
    QSizeF s(width, height);
    if (keepAspect && (s.width() > maxW || s.height() > maxH)) {
        s.scale(maxW, maxH, Qt::KeepAspectRatio);
    }
    s = QSizeF(std::min<qreal>(s.width(), maxW), std::min<qreal>(s.height(), maxH));
    const QSize target(std::max(560, int(s.width())), std::max(300, int(s.height())));
    if (target != m_view->size()) {
        m_view->resize(target);
    }
}

NautilusPreviewer::NautilusPreviewer(QuickLook *parent)
    : QDBusAbstractAdaptor(parent)
    , m_ql(parent)
{
    connect(parent, &QuickLook::selectionEvent, this, &NautilusPreviewer::SelectionEvent);
    connect(parent, &QuickLook::visibleChanged, this, [](bool visible) {
        QDBusMessage msg = QDBusMessage::createSignal(QStringLiteral("/org/gnome/NautilusPreviewer"), QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("PropertiesChanged"));
        msg.setArguments({QStringLiteral("org.gnome.NautilusPreviewer2"), QVariantMap{{QStringLiteral("Visible"), visible}}, QStringList()});
        QDBusConnection::sessionBus().send(msg);
    });
}

bool NautilusPreviewer::visible() const
{
    return m_ql->shown();
}

void NautilusPreviewer::ShowFile(const QString &uri, const QString &windowHandle, bool closeIfShown)
{
    Q_UNUSED(windowHandle)
    m_ql->showUri(uri, closeIfShown);
}

void NautilusPreviewer::Close()
{
    m_ql->close();
}

QuickLookService::QuickLookService(QuickLook *parent)
    : QDBusAbstractAdaptor(parent)
    , m_ql(parent)
{
}

void QuickLookService::Show(const QStringList &files, int index, const QString &host)
{
    m_ql->show(files, index, host);
}

void QuickLookService::Toggle(const QStringList &files, int index, const QString &host)
{
    if (m_ql->shown() && !files.isEmpty() && QFileInfo(QUrl::fromUserInput(files.value(index)).toLocalFile()).absoluteFilePath() == m_ql->path()) {
        m_ql->close();
        return;
    }
    m_ql->show(files, index, host);
}

void QuickLookService::Close()
{
    m_ql->close();
}

bool QuickLookService::IsVisible()
{
    return m_ql->shown();
}
