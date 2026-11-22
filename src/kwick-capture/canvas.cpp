#include "canvas.h"

#include <QCursor>
#include <QFontDatabase>
#include <QFontMetricsF>
#include <QImageWriter>
#include <QPainter>
#include <QPainterPath>
#include <QSaveFile>
#include <QtMath>

#include <cmath>

namespace
{
QPainterPath curve(const QList<QPointF> &points)
{
    QPainterPath path;
    if (points.isEmpty()) {
        return path;
    }
    path.moveTo(points.first());
    if (points.size() == 1) {
        path.lineTo(points.first() + QPointF(0.01, 0.01));
        return path;
    }
    for (int i = 1; i < points.size() - 1; ++i) {
        const QPointF mid = (points.at(i) + points.at(i + 1)) / 2;
        path.quadTo(points.at(i), mid);
    }
    path.lineTo(points.last());
    return path;
}

QFont markFont(qreal size)
{
    QFont font = QFontDatabase::systemFont(QFontDatabase::GeneralFont);
    font.setFamilies({QStringLiteral("Inter"), font.family()});
    font.setPixelSize(qMax(4, qRound(size)));
    font.setWeight(QFont::DemiBold);
    return font;
}

bool isShape(const QString &type)
{
    return type == QLatin1String("line") || type == QLatin1String("arrow") || type == QLatin1String("rect") || type == QLatin1String("ellipse") || type == QLatin1String("redact");
}
}

MarkupCanvas::MarkupCanvas(QQuickItem *parent)
    : QQuickPaintedItem(parent)
{
    setAcceptedMouseButtons(Qt::LeftButton);
    setAntialiasing(true);
    setFillColor(Qt::transparent);
    m_history.append(CanvasState());
    setCursor(Qt::CrossCursor);
}

QString MarkupCanvas::tool() const
{
    return m_tool;
}

void MarkupCanvas::setTool(const QString &tool)
{
    if (tool == m_tool) {
        return;
    }
    const bool wasCrop = m_tool == QLatin1String("crop");
    m_tool = tool;
    if (m_selected >= 0 && tool != QLatin1String("select")) {
        m_selected = -1;
        Q_EMIT selectionChanged();
    }
    if (wasCrop || tool == QLatin1String("crop")) {
        if (wasCrop) {
            cancelCrop();
        }
        layoutView();
    }
    setCursor(tool == QLatin1String("select") ? Qt::ArrowCursor : tool == QLatin1String("text") ? Qt::IBeamCursor : Qt::CrossCursor);
    Q_EMIT toolChanged();
    update();
}

QColor MarkupCanvas::color() const
{
    return m_color;
}

void MarkupCanvas::setColor(const QColor &color)
{
    if (color == m_color) {
        return;
    }
    m_color = color;
    if (m_selected >= 0 && m_selected < state().marks.size() && state().marks.at(m_selected).type != QLatin1String("redact")) {
        CanvasState next = state();
        next.marks[m_selected].color = color;
        m_history.resize(m_index + 1);
        m_history.append(next);
        ++m_index;
        Q_EMIT historyChanged();
        update();
    }
    Q_EMIT colorChanged();
}

qreal MarkupCanvas::strokeWidth() const
{
    return m_strokeWidth;
}

void MarkupCanvas::setStrokeWidth(qreal width)
{
    if (qFuzzyCompare(width, m_strokeWidth)) {
        return;
    }
    m_strokeWidth = width;
    Q_EMIT strokeWidthChanged();
}

QString MarkupCanvas::source() const
{
    return m_source;
}

void MarkupCanvas::setSource(const QString &source)
{
    if (source == m_source) {
        return;
    }
    m_source = source;
    QImage image(source);
    if (!image.isNull()) {
        setImage(image);
    }
    Q_EMIT sourceChanged();
}

void MarkupCanvas::setImage(const QImage &image)
{
    m_opaque = !image.hasAlphaChannel();
    m_image = image.convertToFormat(QImage::Format_ARGB32_Premultiplied);
    m_image.setDevicePixelRatio(1);
    m_history = {CanvasState()};
    m_history.first().crop = QRectF(QPointF(0, 0), m_image.size());
    m_index = 0;
    m_saved = 0;
    m_selected = -1;
    m_scaled = QImage();
    layoutView();
    Q_EMIT sourceChanged();
    Q_EMIT historyChanged();
    update();
}

bool MarkupCanvas::canUndo() const
{
    return m_index > 0;
}

bool MarkupCanvas::canRedo() const
{
    return m_index < m_history.size() - 1;
}

bool MarkupCanvas::modified() const
{
    return m_index != m_saved;
}

bool MarkupCanvas::cropPending() const
{
    return !m_pendingCrop.isEmpty();
}

bool MarkupCanvas::hasSelection() const
{
    return m_selected >= 0;
}

QSize MarkupCanvas::imageSize() const
{
    return m_image.size();
}

QRectF MarkupCanvas::imageRect() const
{
    const QRectF area = visibleArea();
    return QRectF(m_offset, area.size() * m_scale);
}

const CanvasState &MarkupCanvas::state() const
{
    return m_history.at(m_index);
}

QRectF MarkupCanvas::visibleArea() const
{
    if (m_tool == QLatin1String("crop") || state().crop.isEmpty()) {
        return QRectF(QPointF(0, 0), m_image.size());
    }
    return state().crop;
}

void MarkupCanvas::layoutView()
{
    const QRectF area = visibleArea();
    if (area.isEmpty() || width() <= 0 || height() <= 0) {
        return;
    }
    const qreal scale = qMin(qMin(width() / area.width(), height() / area.height()), 2.0);
    const QPointF offset((width() - area.width() * scale) / 2, (height() - area.height() * scale) / 2);
    if (!qFuzzyCompare(scale, m_scale) || m_scaled.isNull()) {
        m_scale = scale;
        m_scaled = QImage();
    }
    m_offset = offset;
    Q_EMIT viewChanged();
}

void MarkupCanvas::geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry)
{
    QQuickPaintedItem::geometryChange(newGeometry, oldGeometry);
    layoutView();
    update();
}

QPointF MarkupCanvas::toImage(const QPointF &point) const
{
    return (point - m_offset) / m_scale + visibleArea().topLeft();
}

void MarkupCanvas::push()
{
    m_history.resize(m_index + 1);
    m_history.append(state());
    ++m_index;
}

void MarkupCanvas::drawMark(QPainter *painter, const Mark &mark) const
{
    painter->save();
    if (mark.type == QLatin1String("redact")) {
        const QRect area = QRectF(mark.points.at(0), mark.points.at(1)).normalized().toAlignedRect().intersected(m_image.rect());
        if (!area.isEmpty()) {
            const int block = qMax(6, qMax(m_image.width(), m_image.height()) / 120);
            const QImage piece = m_image.copy(area);
            const QImage small = piece.scaled(qMax(1, area.width() / block), qMax(1, area.height() / block), Qt::IgnoreAspectRatio, Qt::SmoothTransformation);
            const QImage blocky = small.scaled(area.size(), Qt::IgnoreAspectRatio, Qt::FastTransformation);
            painter->drawImage(area.topLeft(), blocky);
        }
        painter->restore();
        return;
    }
    QPen pen(mark.color, mark.width, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin);
    if (mark.type == QLatin1String("highlighter")) {
        QColor tint = mark.color;
        tint.setAlphaF(0.42);
        pen = QPen(tint, mark.width * 4, Qt::SolidLine, Qt::FlatCap, Qt::RoundJoin);
        painter->strokePath(curve(mark.points), pen);
    } else if (mark.type == QLatin1String("pen")) {
        painter->strokePath(curve(mark.points), pen);
    } else if (mark.type == QLatin1String("line")) {
        painter->setPen(pen);
        painter->drawLine(mark.points.at(0), mark.points.at(1));
    } else if (mark.type == QLatin1String("arrow")) {
        const QPointF from = mark.points.at(0);
        const QPointF to = mark.points.at(1);
        const QLineF line(from, to);
        const qreal head = qMin(line.length() * 0.6, mark.width * 3.2 + 10);
        const qreal angle = std::atan2(to.y() - from.y(), to.x() - from.x());
        const qreal spread = qDegreesToRadians(26.0);
        const QPointF left = to - QPointF(std::cos(angle - spread), std::sin(angle - spread)) * head;
        const QPointF right = to - QPointF(std::cos(angle + spread), std::sin(angle + spread)) * head;
        const QPointF base = to - QPointF(std::cos(angle), std::sin(angle)) * head * 0.8;
        painter->setPen(pen);
        painter->drawLine(from, base);
        QPainterPath tip;
        tip.moveTo(to);
        tip.lineTo(left);
        tip.lineTo(right);
        tip.closeSubpath();
        painter->setPen(QPen(mark.color, mark.width * 0.6, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin));
        painter->setBrush(mark.color);
        painter->drawPath(tip);
    } else if (mark.type == QLatin1String("rect")) {
        painter->setPen(pen);
        painter->setBrush(Qt::NoBrush);
        painter->drawRoundedRect(QRectF(mark.points.at(0), mark.points.at(1)).normalized(), mark.width, mark.width);
    } else if (mark.type == QLatin1String("ellipse")) {
        painter->setPen(pen);
        painter->setBrush(Qt::NoBrush);
        painter->drawEllipse(QRectF(mark.points.at(0), mark.points.at(1)).normalized());
    } else if (mark.type == QLatin1String("text")) {
        painter->setFont(markFont(mark.fontSize));
        painter->setPen(mark.color);
        const QFontMetricsF metrics(painter->font());
        const QStringList lines = mark.text.split(QLatin1Char('\n'));
        qreal y = mark.points.at(0).y() + metrics.ascent();
        for (const QString &line : lines) {
            painter->drawText(QPointF(mark.points.at(0).x(), y), line);
            y += metrics.lineSpacing();
        }
    }
    painter->restore();
}

QRectF MarkupCanvas::bounds(const Mark &mark) const
{
    if (mark.type == QLatin1String("text")) {
        const QFontMetricsF metrics(markFont(mark.fontSize));
        qreal w = 0;
        const QStringList lines = mark.text.split(QLatin1Char('\n'));
        for (const QString &line : lines) {
            w = qMax(w, metrics.horizontalAdvance(line));
        }
        return QRectF(mark.points.at(0), QSizeF(w, metrics.lineSpacing() * lines.size()));
    }
    QRectF box;
    for (const QPointF &point : mark.points) {
        box = box.isNull() ? QRectF(point, QSizeF(0.01, 0.01)) : box.united(QRectF(point, QSizeF(0.01, 0.01)));
    }
    const qreal grow = mark.type == QLatin1String("highlighter") ? mark.width * 2 : mark.width;
    return box.adjusted(-grow, -grow, grow, grow);
}

int MarkupCanvas::hit(const QPointF &point) const
{
    const qreal tolerance = 6 / m_scale;
    for (int i = state().marks.size() - 1; i >= 0; --i) {
        if (bounds(state().marks.at(i)).adjusted(-tolerance, -tolerance, tolerance, tolerance).contains(point)) {
            return i;
        }
    }
    return -1;
}

void MarkupCanvas::paint(QPainter *painter)
{
    if (m_image.isNull()) {
        return;
    }
    const QRectF area = visibleArea();
    const QRectF target(m_offset, area.size() * m_scale);
    painter->setRenderHint(QPainter::Antialiasing);
    painter->setRenderHint(QPainter::SmoothPixmapTransform);
    if (m_scaled.isNull() || m_scaled.size() != (QSizeF(m_image.size()) * m_scale).toSize()) {
        m_scaled = m_image.scaled((QSizeF(m_image.size()) * m_scale).toSize(), Qt::IgnoreAspectRatio, Qt::SmoothTransformation);
    }
    painter->save();
    painter->setClipRect(target);
    painter->drawImage(m_offset - area.topLeft() * m_scale, m_scaled);
    painter->translate(m_offset);
    painter->scale(m_scale, m_scale);
    painter->translate(-area.topLeft());
    for (const Mark &mark : state().marks) {
        drawMark(painter, mark);
    }
    if (m_drawing) {
        drawMark(painter, m_live);
    }
    if (m_selected >= 0 && m_selected < state().marks.size()) {
        QPen dash(m_accent, 1.5 / m_scale, Qt::DashLine);
        painter->setPen(dash);
        painter->setBrush(Qt::NoBrush);
        painter->drawRect(bounds(state().marks.at(m_selected)));
    }
    painter->restore();

    if (m_tool == QLatin1String("crop")) {
        const QRectF crop = m_pendingCrop.isEmpty() ? state().crop : m_pendingCrop;
        const QRectF view(m_offset + (crop.topLeft() - area.topLeft()) * m_scale, crop.size() * m_scale);
        QPainterPath outside;
        outside.addRect(target);
        QPainterPath inside;
        inside.addRect(view);
        painter->fillPath(outside.subtracted(inside), QColor(0, 0, 0, 120));
        painter->setPen(QPen(Qt::white, 1.5));
        painter->setBrush(Qt::NoBrush);
        painter->drawRect(view);
        painter->setPen(QPen(QColor(255, 255, 255, 110), 1));
        for (int i = 1; i < 3; ++i) {
            painter->drawLine(QPointF(view.left() + view.width() * i / 3, view.top()), QPointF(view.left() + view.width() * i / 3, view.bottom()));
            painter->drawLine(QPointF(view.left(), view.top() + view.height() * i / 3), QPointF(view.right(), view.top() + view.height() * i / 3));
        }
        painter->setPen(QPen(Qt::white, 4, Qt::SolidLine, Qt::SquareCap));
        const qreal k = qMin<qreal>(18, qMin(view.width(), view.height()) / 2);
        for (const QPointF &corner : {view.topLeft(), view.topRight(), view.bottomLeft(), view.bottomRight()}) {
            const qreal sx = std::abs(corner.x() - view.left()) < 0.5 ? 1 : -1;
            const qreal sy = std::abs(corner.y() - view.top()) < 0.5 ? 1 : -1;
            painter->drawLine(corner, corner + QPointF(sx * k, 0));
            painter->drawLine(corner, corner + QPointF(0, sy * k));
        }
    }
}

void MarkupCanvas::mousePressEvent(QMouseEvent *event)
{
    if (m_image.isNull()) {
        return;
    }
    forceActiveFocus();
    const QPointF at = toImage(event->position());
    if (m_tool == QLatin1String("text")) {
        const int index = hit(at);
        if (index >= 0 && state().marks.at(index).type == QLatin1String("text")) {
            m_selected = index;
            Q_EMIT selectionChanged();
            m_tool = QStringLiteral("select");
            Q_EMIT toolChanged();
        } else {
            const qreal size = qMax(14.0, m_strokeWidth * 5 + 6);
            Q_EMIT textRequested(event->position().x(), event->position().y() - size * 0.6, size);
            event->accept();
            return;
        }
    }
    if (m_tool == QLatin1String("select")) {
        m_selected = hit(at);
        Q_EMIT selectionChanged();
        if (m_selected >= 0) {
            m_dragFrom = at;
            m_dragOrigin = state().marks.at(m_selected).points;
            m_moved = false;
        }
        update();
        event->accept();
        return;
    }
    if (m_tool == QLatin1String("crop")) {
        m_cropDrag = true;
        m_dragFrom = at;
        m_pendingCrop = QRectF();
        event->accept();
        return;
    }
    m_drawing = true;
    m_live = Mark();
    m_live.type = m_tool;
    m_live.color = m_color;
    m_live.width = m_strokeWidth / m_scale;
    m_live.points = {at};
    if (isShape(m_tool)) {
        m_live.points.append(at);
    }
    event->accept();
    update();
}

void MarkupCanvas::mouseMoveEvent(QMouseEvent *event)
{
    const QPointF at = toImage(event->position());
    if (m_cropDrag) {
        const QRectF all(QPointF(0, 0), m_image.size());
        m_pendingCrop = QRectF(m_dragFrom, at).normalized().intersected(all);
        Q_EMIT cropPendingChanged();
        update();
        return;
    }
    if (m_tool == QLatin1String("select") && m_selected >= 0) {
        if (!m_moved) {
            push();
            m_moved = true;
        }
        const QPointF delta = at - m_dragFrom;
        QList<QPointF> &points = m_history[m_index].marks[m_selected].points;
        for (int i = 0; i < points.size(); ++i) {
            points[i] = m_dragOrigin.at(i) + delta;
        }
        update();
        return;
    }
    if (!m_drawing) {
        return;
    }
    if (isShape(m_live.type)) {
        QPointF end = at;
        if (event->modifiers() & Qt::ShiftModifier) {
            const QPointF d = at - m_live.points.first();
            if (m_live.type == QLatin1String("line") || m_live.type == QLatin1String("arrow")) {
                const qreal angle = std::round(std::atan2(d.y(), d.x()) / (M_PI / 4)) * (M_PI / 4);
                const qreal length = std::hypot(d.x(), d.y());
                end = m_live.points.first() + QPointF(std::cos(angle), std::sin(angle)) * length;
            } else {
                const qreal side = qMax(std::abs(d.x()), std::abs(d.y()));
                end = m_live.points.first() + QPointF(d.x() < 0 ? -side : side, d.y() < 0 ? -side : side);
            }
        }
        m_live.points[1] = end;
    } else if (QLineF(m_live.points.last(), at).length() * m_scale > 1.2) {
        m_live.points.append(at);
    }
    update();
}

void MarkupCanvas::mouseReleaseEvent(QMouseEvent *)
{
    if (m_cropDrag) {
        m_cropDrag = false;
        if (m_pendingCrop.width() * m_scale < 6 || m_pendingCrop.height() * m_scale < 6) {
            m_pendingCrop = QRectF();
        }
        Q_EMIT cropPendingChanged();
        update();
        return;
    }
    if (m_moved) {
        m_moved = false;
        Q_EMIT historyChanged();
        return;
    }
    if (!m_drawing) {
        return;
    }
    m_drawing = false;
    const QRectF box = bounds(m_live);
    const bool tiny = isShape(m_live.type) && QLineF(m_live.points.at(0), m_live.points.at(1)).length() * m_scale < 4;
    if (!tiny && !box.isEmpty()) {
        push();
        m_history[m_index].marks.append(m_live);
        Q_EMIT historyChanged();
    }
    update();
}

void MarkupCanvas::undo()
{
    if (m_index == 0) {
        return;
    }
    --m_index;
    m_selected = -1;
    Q_EMIT selectionChanged();
    layoutView();
    Q_EMIT historyChanged();
    update();
}

void MarkupCanvas::redo()
{
    if (m_index >= m_history.size() - 1) {
        return;
    }
    ++m_index;
    m_selected = -1;
    Q_EMIT selectionChanged();
    layoutView();
    Q_EMIT historyChanged();
    update();
}

void MarkupCanvas::applyCrop()
{
    if (m_pendingCrop.isEmpty()) {
        return;
    }
    push();
    m_history[m_index].crop = m_pendingCrop.toAlignedRect().intersected(m_image.rect());
    m_pendingCrop = QRectF();
    Q_EMIT cropPendingChanged();
    Q_EMIT historyChanged();
    setTool(QStringLiteral("select"));
    layoutView();
    update();
}

void MarkupCanvas::cancelCrop()
{
    if (m_pendingCrop.isEmpty()) {
        return;
    }
    m_pendingCrop = QRectF();
    Q_EMIT cropPendingChanged();
    update();
}

void MarkupCanvas::addText(qreal x, qreal y, const QString &text)
{
    if (text.trimmed().isEmpty()) {
        return;
    }
    Mark mark;
    mark.type = QStringLiteral("text");
    mark.color = m_color;
    mark.text = text;
    mark.fontSize = qMax(14.0, m_strokeWidth * 5 + 6) / m_scale;
    mark.points = {toImage(QPointF(x, y))};
    push();
    m_history[m_index].marks.append(mark);
    Q_EMIT historyChanged();
    update();
}

void MarkupCanvas::deleteSelected()
{
    if (m_selected < 0 || m_selected >= state().marks.size()) {
        return;
    }
    push();
    m_history[m_index].marks.removeAt(m_selected);
    m_selected = -1;
    Q_EMIT selectionChanged();
    Q_EMIT historyChanged();
    update();
}

QImage MarkupCanvas::render() const
{
    if (m_image.isNull()) {
        return {};
    }
    const QRect crop = (state().crop.isEmpty() ? QRectF(m_image.rect()) : state().crop).toAlignedRect().intersected(m_image.rect());
    QImage out(crop.size(), QImage::Format_ARGB32_Premultiplied);
    out.fill(Qt::transparent);
    QPainter painter(&out);
    painter.setRenderHint(QPainter::Antialiasing);
    painter.setRenderHint(QPainter::TextAntialiasing);
    painter.translate(-crop.topLeft());
    painter.drawImage(0, 0, m_image);
    for (const Mark &mark : state().marks) {
        drawMark(&painter, mark);
    }
    painter.end();
    return out;
}

bool MarkupCanvas::saveTo(const QString &path)
{
    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly)) {
        return false;
    }
    const QString suffix = path.section(QLatin1Char('.'), -1).toLower();
    const QByteArray format = suffix == QLatin1String("jpg") || suffix == QLatin1String("jpeg") ? QByteArrayLiteral("JPG") : QByteArrayLiteral("PNG");
    QImage image = render();
    if (format == "JPG" || m_opaque) {
        image = image.convertToFormat(QImage::Format_RGB32);
    }
    if (!image.save(&file, format.constData(), format == "JPG" ? 92 : -1) || !file.commit()) {
        return false;
    }
    markSaved();
    return true;
}

void MarkupCanvas::markSaved()
{
    m_saved = m_index;
    Q_EMIT historyChanged();
}
