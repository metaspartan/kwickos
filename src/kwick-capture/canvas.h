#pragma once

#include <QColor>
#include <QImage>
#include <QQuickPaintedItem>
#include <QtQml/qqmlregistration.h>

struct Mark {
    QString type;
    QList<QPointF> points;
    QColor color;
    qreal width = 4;
    QString text;
    qreal fontSize = 24;
};

struct CanvasState {
    QList<Mark> marks;
    QRectF crop;
};

class MarkupCanvas : public QQuickPaintedItem
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QString tool READ tool WRITE setTool NOTIFY toolChanged)
    Q_PROPERTY(QColor color READ color WRITE setColor NOTIFY colorChanged)
    Q_PROPERTY(qreal strokeWidth READ strokeWidth WRITE setStrokeWidth NOTIFY strokeWidthChanged)
    Q_PROPERTY(QString source READ source WRITE setSource NOTIFY sourceChanged)
    Q_PROPERTY(bool canUndo READ canUndo NOTIFY historyChanged)
    Q_PROPERTY(bool canRedo READ canRedo NOTIFY historyChanged)
    Q_PROPERTY(bool modified READ modified NOTIFY historyChanged)
    Q_PROPERTY(bool cropPending READ cropPending NOTIFY cropPendingChanged)
    Q_PROPERTY(bool hasSelection READ hasSelection NOTIFY selectionChanged)
    Q_PROPERTY(QSize imageSize READ imageSize NOTIFY sourceChanged)
    Q_PROPERTY(QRectF imageRect READ imageRect NOTIFY viewChanged)
    Q_PROPERTY(QColor accent MEMBER m_accent)

public:
    explicit MarkupCanvas(QQuickItem *parent = nullptr);

    QString tool() const;
    void setTool(const QString &tool);
    QColor color() const;
    void setColor(const QColor &color);
    qreal strokeWidth() const;
    void setStrokeWidth(qreal width);
    QString source() const;
    void setSource(const QString &source);
    bool canUndo() const;
    bool canRedo() const;
    bool modified() const;
    bool cropPending() const;
    bool hasSelection() const;
    QSize imageSize() const;
    QRectF imageRect() const;

    void setImage(const QImage &image);
    QImage render() const;

    Q_INVOKABLE void undo();
    Q_INVOKABLE void redo();
    Q_INVOKABLE void applyCrop();
    Q_INVOKABLE void cancelCrop();
    Q_INVOKABLE void addText(qreal x, qreal y, const QString &text);
    Q_INVOKABLE void deleteSelected();
    Q_INVOKABLE bool saveTo(const QString &path);
    Q_INVOKABLE void markSaved();

    void paint(QPainter *painter) override;

Q_SIGNALS:
    void toolChanged();
    void colorChanged();
    void strokeWidthChanged();
    void sourceChanged();
    void historyChanged();
    void cropPendingChanged();
    void selectionChanged();
    void viewChanged();
    void textRequested(qreal x, qreal y, qreal fontSize);

protected:
    void mousePressEvent(QMouseEvent *event) override;
    void mouseMoveEvent(QMouseEvent *event) override;
    void mouseReleaseEvent(QMouseEvent *event) override;
    void geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry) override;

private:
    QRectF visibleArea() const;
    void layoutView();
    QPointF toImage(const QPointF &point) const;
    void push();
    void drawMark(QPainter *painter, const Mark &mark) const;
    QRectF bounds(const Mark &mark) const;
    int hit(const QPointF &point) const;
    const CanvasState &state() const;

    QImage m_image;
    QImage m_scaled;
    QString m_source;
    QString m_tool = QStringLiteral("arrow");
    QColor m_color = QColor(0xff, 0x3b, 0x30);
    QColor m_accent = QColor(0xff, 0x9f, 0x0a);
    qreal m_strokeWidth = 4;
    QList<CanvasState> m_history;
    int m_index = 0;
    int m_saved = 0;
    bool m_drawing = false;
    bool m_opaque = true;
    Mark m_live;
    int m_selected = -1;
    QPointF m_dragFrom;
    QList<QPointF> m_dragOrigin;
    bool m_moved = false;
    QRectF m_pendingCrop;
    bool m_cropDrag = false;
    qreal m_scale = 1;
    QPointF m_offset;
};
