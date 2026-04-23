#pragma once

#include <QString>
#include <QWidget>

class QHBoxLayout;
class QToolButton;

/*
 * BreadcrumbBar — a row of clickable ancestor buttons.
 *
 * Clicking a segment emits pathPicked(<path to that ancestor>). Rebuilds
 * cheaply whenever setPath is called. On Windows the first segment is the
 * drive letter (e.g. "C:"), on POSIX it's the root "/".
 */
class BreadcrumbBar : public QWidget {
    Q_OBJECT
public:
    explicit BreadcrumbBar(QWidget *parent = nullptr);

    void setPath(const QString &path);

signals:
    void pathPicked(const QString &path);

private:
    void clearButtons();
    QToolButton *makeSegment(const QString &label, const QString &path);

    QHBoxLayout *m_layout = nullptr;
};
