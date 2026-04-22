#include "ButtonBank.h"

#include <QFrame>
#include <QPushButton>
#include <QSettings>
#include <QVBoxLayout>

ButtonBank::ButtonBank(QWidget *parent)
    : QWidget(parent) {
    m_layout = new QVBoxLayout(this);
    m_layout->setContentsMargins(4, 4, 4, 4);
    m_layout->setSpacing(4);

    auto *copyBtn    = makeButton(QStringLiteral("Copy"),    true);
    auto *moveBtn    = makeButton(QStringLiteral("Move"),    true);
    auto *deleteBtn  = makeButton(QStringLiteral("Delete"),  true);
    auto *renameBtn  = makeButton(QStringLiteral("Rename"),  true);
    auto *makeDirBtn = makeButton(QStringLiteral("MakeDir"), true);
    auto *infoBtn    = makeButton(QStringLiteral("Info"),    true);
    auto *filterBtn  = makeButton(QStringLiteral("Filter"),  true);

    connect(copyBtn,    &QPushButton::clicked, this, &ButtonBank::copyClicked);
    connect(moveBtn,    &QPushButton::clicked, this, &ButtonBank::moveClicked);
    connect(deleteBtn,  &QPushButton::clicked, this, &ButtonBank::deleteClicked);
    connect(renameBtn,  &QPushButton::clicked, this, &ButtonBank::renameClicked);
    connect(makeDirBtn, &QPushButton::clicked, this, &ButtonBank::makeDirClicked);
    connect(infoBtn,    &QPushButton::clicked, this, &ButtonBank::infoClicked);
    connect(filterBtn,  &QPushButton::clicked, this, &ButtonBank::filterClicked);

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

    m_layout->addWidget(copyBtn);
    m_layout->addWidget(moveBtn);
    m_layout->addWidget(deleteBtn);
    m_layout->addWidget(renameBtn);
    m_layout->addWidget(makeDirBtn);
    m_layout->addWidget(infoBtn);
    m_layout->addWidget(filterBtn);
    m_layout->addWidget(parentBtn);
    m_layout->addWidget(rootBtn);
    m_layout->addWidget(refreshBtn);
    m_layout->addWidget(allBtn);
    m_layout->addWidget(noneBtn);

    /* Thin separator + "Buttons…" management entry before custom buttons. */
    auto *sep = new QFrame(this);
    sep->setFrameShape(QFrame::HLine);
    sep->setFrameShadow(QFrame::Sunken);
    m_layout->addWidget(sep);

    auto *manageBtn = makeButton(QStringLiteral("Buttons…"), true);
    manageBtn->setToolTip(tr("Add / edit custom buttons"));
    connect(manageBtn, &QPushButton::clicked, this, &ButtonBank::manageCustomRequested);
    m_layout->addWidget(manageBtn);

    m_layout->addStretch(1);

    load();
    rebuildCustomRows();

    setFixedWidth(110);
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

void ButtonBank::addCustomButton(const CustomButton &b) {
    m_custom.append(b);
    save();
    rebuildCustomRows();
}

void ButtonBank::removeCustomAt(int index) {
    if (index < 0 || index >= m_custom.size()) return;
    m_custom.removeAt(index);
    save();
    rebuildCustomRows();
}

void ButtonBank::replaceCustom(int index, const CustomButton &b) {
    if (index < 0 || index >= m_custom.size()) return;
    m_custom[index] = b;
    save();
    rebuildCustomRows();
}

void ButtonBank::rebuildCustomRows() {
    /* Drop the stretch (always the last item), tear down old custom buttons,
     * build fresh ones, then re-append the stretch. */
    if (m_layout->count() > 0) {
        auto *last = m_layout->takeAt(m_layout->count() - 1);
        delete last;
    }
    for (QPushButton *b : m_customButtons) {
        m_layout->removeWidget(b);
        b->deleteLater();
    }
    m_customButtons.clear();

    for (const CustomButton &cb : m_custom) {
        auto *b = makeButton(cb.label.isEmpty() ? cb.command : cb.label, true);
        b->setToolTip(cb.command);
        const QString cmd = cb.command;
        connect(b, &QPushButton::clicked, this, [this, cmd]{ emit customTriggered(cmd); });
        m_layout->addWidget(b);
        m_customButtons.append(b);
    }

    m_layout->addStretch(1);
}

void ButtonBank::load() {
    QSettings s;
    const int n = s.beginReadArray(QStringLiteral("buttons"));
    m_custom.clear();
    m_custom.reserve(n);
    for (int i = 0; i < n; ++i) {
        s.setArrayIndex(i);
        CustomButton b;
        b.label   = s.value(QStringLiteral("label")).toString();
        b.command = s.value(QStringLiteral("command")).toString();
        if (!b.command.isEmpty()) m_custom.append(b);
    }
    s.endArray();
}

void ButtonBank::save() {
    QSettings s;
    s.beginWriteArray(QStringLiteral("buttons"), m_custom.size());
    for (int i = 0; i < m_custom.size(); ++i) {
        s.setArrayIndex(i);
        s.setValue(QStringLiteral("label"),   m_custom[i].label);
        s.setValue(QStringLiteral("command"), m_custom[i].command);
    }
    s.endArray();
}
