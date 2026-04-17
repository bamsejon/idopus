#include "MainWindow.h"
#include "ListerWidget.h"

#include <QAction>
#include <QApplication>
#include <QKeySequence>
#include <QSplitter>
#include <QToolBar>

MainWindow::MainWindow(const QString &leftPath, const QString &rightPath,
                       QWidget *parent)
    : QMainWindow(parent) {
    m_left  = new ListerWidget(leftPath,  this);
    m_right = new ListerWidget(rightPath, this);

    auto *splitter = new QSplitter(Qt::Horizontal, this);
    splitter->addWidget(m_left);
    splitter->addWidget(m_right);
    splitter->setChildrenCollapsible(false);
    splitter->setSizes({1, 1});
    setCentralWidget(splitter);

    QToolBar *tb = addToolBar(QStringLiteral("Navigation"));
    tb->setMovable(false);

    m_actParent = tb->addAction(QStringLiteral("↑ Parent"));
    m_actParent->setShortcut(QKeySequence(Qt::ALT | Qt::Key_Up));
    connect(m_actParent, &QAction::triggered, this, &MainWindow::onParent);

    m_actRefresh = tb->addAction(QStringLiteral("Refresh"));
    m_actRefresh->setShortcut(QKeySequence::Refresh);
    connect(m_actRefresh, &QAction::triggered, this, &MainWindow::onRefresh);

    m_actHome = tb->addAction(QStringLiteral("Home"));
    m_actHome->setShortcut(QKeySequence(Qt::ALT | Qt::Key_Home));
    connect(m_actHome, &QAction::triggered, this, &MainWindow::onHome);

    connect(m_left,  &ListerWidget::pathChanged, this, [this](const QString&) { updateTitle(); });
    connect(m_right, &ListerWidget::pathChanged, this, [this](const QString&) { updateTitle(); });

    connect(qApp, &QApplication::focusChanged,
            this, &MainWindow::onFocusChanged);

    setActive(m_left);
}

void MainWindow::setActive(ListerWidget *lister) {
    if (lister == m_active) return;
    if (m_active) m_active->setActive(false);
    m_active = lister;
    if (m_active) m_active->setActive(true);
    updateTitle();
}

void MainWindow::updateTitle() {
    if (!m_active) { setWindowTitle(QStringLiteral("iDOpus")); return; }
    setWindowTitle(QStringLiteral("iDOpus — ") + m_active->currentPath());
}

void MainWindow::onFocusChanged(QWidget * /*old*/, QWidget *now) {
    for (QWidget *w = now; w; w = w->parentWidget()) {
        if (w == m_left)  { setActive(m_left);  return; }
        if (w == m_right) { setActive(m_right); return; }
    }
    /* focus went to toolbar or outside — keep current active */
}

void MainWindow::onParent()  { if (m_active) m_active->goParent(); }
void MainWindow::onRefresh() { if (m_active) m_active->refresh();  }
void MainWindow::onHome()    { if (m_active) m_active->goHome();   }
