#include "ButtonBank.h"

#include <QPushButton>
#include <QVBoxLayout>

ButtonBank::ButtonBank(QWidget *parent)
    : QWidget(parent) {
    auto *lay = new QVBoxLayout(this);
    lay->setContentsMargins(4, 4, 4, 4);
    lay->setSpacing(4);

    /* File-op buttons: disabled for now, but signals exist for future wiring. */
    auto *copyBtn    = makeButton(QStringLiteral("Copy"),    false);
    auto *moveBtn    = makeButton(QStringLiteral("Move"),    false);
    auto *deleteBtn  = makeButton(QStringLiteral("Delete"),  false);
    auto *renameBtn  = makeButton(QStringLiteral("Rename"),  false);
    auto *makeDirBtn = makeButton(QStringLiteral("MakeDir"), false);
    auto *infoBtn    = makeButton(QStringLiteral("Info"),    false);
    auto *filterBtn  = makeButton(QStringLiteral("Filter"),  false);

    connect(copyBtn,    &QPushButton::clicked, this, &ButtonBank::copyClicked);
    connect(moveBtn,    &QPushButton::clicked, this, &ButtonBank::moveClicked);
    connect(deleteBtn,  &QPushButton::clicked, this, &ButtonBank::deleteClicked);
    connect(renameBtn,  &QPushButton::clicked, this, &ButtonBank::renameClicked);
    connect(makeDirBtn, &QPushButton::clicked, this, &ButtonBank::makeDirClicked);
    connect(infoBtn,    &QPushButton::clicked, this, &ButtonBank::infoClicked);
    connect(filterBtn,  &QPushButton::clicked, this, &ButtonBank::filterClicked);

    /* Wired: operate on whichever pane is active. */
    auto *parentBtn  = makeButton(QStringLiteral("Parent"),  true);
    auto *rootBtn    = makeButton(QStringLiteral("Root"),    true);
    auto *refreshBtn = makeButton(QStringLiteral("Refresh"), true);
    auto *allBtn     = makeButton(QStringLiteral("All"),     true);
    auto *noneBtn    = makeButton(QStringLiteral("None"),    true);

    connect(parentBtn,  &QPushButton::clicked, this, &ButtonBank::parentClicked);
    connect(rootBtn,    &QPushButton::clicked, this, &ButtonBank::rootClicked);
    connect(refreshBtn, &QPushButton::clicked, this, &ButtonBank::refreshClicked);
    connect(allBtn,     &QPushButton::clicked, this, &ButtonBank::allClicked);
    connect(noneBtn,    &QPushButton::clicked, this, &ButtonBank::noneClicked);

    lay->addWidget(copyBtn);
    lay->addWidget(moveBtn);
    lay->addWidget(deleteBtn);
    lay->addWidget(renameBtn);
    lay->addWidget(makeDirBtn);
    lay->addWidget(infoBtn);
    lay->addWidget(filterBtn);
    lay->addWidget(parentBtn);
    lay->addWidget(rootBtn);
    lay->addWidget(refreshBtn);
    lay->addWidget(allBtn);
    lay->addWidget(noneBtn);

    setFixedWidth(100);
}

QPushButton *ButtonBank::makeButton(const QString &text, bool enabled) {
    auto *b = new QPushButton(text, this);
    b->setAutoDefault(false);
    b->setDefault(false);
    b->setEnabled(enabled);
    b->setStyleSheet(QStringLiteral("QPushButton { padding: 4px 6px; }"));
    QFont f = b->font();
    f.setPointSizeF(f.pointSizeF() * 0.9);
    b->setFont(f);
    b->setSizePolicy(QSizePolicy::Preferred, QSizePolicy::MinimumExpanding);
    return b;
}
