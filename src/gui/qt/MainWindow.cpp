#include "MainWindow.h"
#include "ListerWidget.h"
#include "ButtonBank.h"

#include <QApplication>
#include <QSplitter>

MainWindow::MainWindow(const QString &leftPath, const QString &rightPath,
                       QWidget *parent)
    : QMainWindow(parent) {
    m_left  = new ListerWidget(leftPath,  this);
    m_right = new ListerWidget(rightPath, this);
    m_bank  = new ButtonBank(this);

    auto *splitter = new QSplitter(Qt::Horizontal, this);
    splitter->addWidget(m_left);
    splitter->addWidget(m_bank);
    splitter->addWidget(m_right);
    splitter->setChildrenCollapsible(false);
    splitter->setStretchFactor(0, 1);
    splitter->setStretchFactor(1, 0);
    splitter->setStretchFactor(2, 1);
    setCentralWidget(splitter);

    connect(m_bank, &ButtonBank::parentClicked,  this, [this]{ if (m_active) m_active->goParent();   });
    connect(m_bank, &ButtonBank::rootClicked,    this, [this]{ if (m_active) m_active->goRoot();     });
    connect(m_bank, &ButtonBank::refreshClicked, this, [this]{ if (m_active) m_active->refresh();    });
    connect(m_bank, &ButtonBank::allClicked,     this, [this]{ if (m_active) m_active->selectAll();  });
    connect(m_bank, &ButtonBank::noneClicked,    this, [this]{ if (m_active) m_active->selectNone(); });

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
    /* focus went elsewhere — keep current active */
}
