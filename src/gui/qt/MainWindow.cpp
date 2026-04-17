#include "MainWindow.h"
#include "ListerWidget.h"

#include <QAction>
#include <QKeySequence>
#include <QToolBar>

MainWindow::MainWindow(const QString &initialPath, QWidget *parent)
    : QMainWindow(parent) {
    m_lister = new ListerWidget(initialPath, this);
    setCentralWidget(m_lister);

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

    setWindowTitle(QStringLiteral("iDOpus — ") + initialPath);
    connect(m_lister, &ListerWidget::pathChanged, this,
            [this](const QString &p) { setWindowTitle(QStringLiteral("iDOpus — ") + p); });
}

void MainWindow::onParent()  { m_lister->goParent();  }
void MainWindow::onRefresh() { m_lister->refresh();   }
void MainWindow::onHome()    { m_lister->goHome();    }
